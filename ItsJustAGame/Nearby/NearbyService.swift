import Foundation
import MultipeerConnectivity
import Observation
import UIKit

/// Everything device-to-device for nearby (no-internet) games, built on
/// MultipeerConnectivity — Bluetooth and peer-to-peer Wi-Fi, no router, no
/// internet. Works on a plane with the radios switched on.
///
/// The host is the mailbox: it keeps the same record store CloudKit would
/// hold, and peers' put/get calls arrive here as tiny request/response
/// packets. The game's own end-to-end encryption is unchanged on top
/// (MultipeerConnectivity adds its own transport encryption underneath).
///
/// One shared instance lives for the app: hosting or browsing starts and
/// stops around the nearby screens, and the session survives while a
/// nearby game is being played.
@Observable
final class NearbyService: NSObject, @unchecked Sendable {
    @MainActor static let shared = NearbyService()

    /// Bonjour service type — also declared in Info.plist NSBonjourServices.
    static let serviceType = "ijag"

    // MARK: - Observable state (main-actor mutated)

    /// Peers connected to the host, in join order, with the player name
    /// each sent in its hello.
    private(set) var roster: [NearbyPeer] = []
    /// Hosts a joiner can currently see.
    private(set) var foundHosts: [NearbyHost] = []
    /// Joiner-side connection progress.
    private(set) var joinState: JoinState = .idle
    /// Set when the host starts the game and this joiner gets its slot/key.
    private(set) var receivedWelcome: NearbyWelcome?

    struct NearbyPeer: Identifiable, Hashable {
        let peerID: MCPeerID
        var name: String
        var id: String { peerID.displayName }
    }

    struct NearbyHost: Identifiable, Hashable {
        let peerID: MCPeerID
        var name: String
        var id: String { peerID.displayName }
    }

    enum JoinState: Equatable {
        case idle
        case browsing
        case connecting(String)
        case connected(String)   // waiting for the host to start
    }

    // MARK: - Wire packets

    enum Packet: Codable {
        /// Joiner → host, right after connecting: the player's name (and
        /// wire version, so version gating keeps working offline).
        case hello(name: String, protocolVersion: Int)
        /// Host → joiner when the game starts (or on reconnect): your
        /// identity in the game.
        case welcome(gameID: String, slot: Int, keyBase64URL: String)
        /// Peer → host: store this record (create-if-absent).
        case put(id: String, body: Data)
        /// Peer → host: which of these exist?
        case get(requestID: UUID, ids: [String])
        /// Host → peer: the answer.
        case records(requestID: UUID, found: [String: Data])
    }

    struct NearbyWelcome: Equatable {
        let gameID: String
        let slot: Int
        let keyBase64URL: String
    }

    // MARK: - Private state

    private var myPeerID: MCPeerID?
    private var mcSession: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var isHosting = false
    /// Host: the peer each game slot belongs to, so a reconnecting player
    /// gets the same seat back.
    private var slotAssignments: [String: Int] = [:]   // name → slot
    private var activeWelcomes: [MCPeerID: NearbyWelcome] = [:]
    private var startedGame: (gameID: String, key: String)?

    /// The host's record store + the joiner's pending gets. Touched from
    /// delegate queues and transport tasks — always under the lock.
    private let lock = NSLock()
    private var records: [String: Data] = [:]
    private var pendingGets: [UUID: CheckedContinuation<[String: Data], Never>] = [:]
    private var hostPeer: MCPeerID?

    // MARK: - Session lifecycle

    private func makeSession(name: String) -> MCSession {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        let peerID = MCPeerID(displayName: trimmed.isEmpty ? UIDevice.current.name : trimmed)
        myPeerID = peerID
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }

    /// Host side: open the doors. Every invitation is accepted; players
    /// appear in `roster` once their hello arrives.
    @MainActor
    func startHosting(hostName: String) {
        stop()
        isHosting = true
        let session = makeSession(name: hostName)
        mcSession = session
        let advertiser = MCNearbyServiceAdvertiser(
            peer: session.myPeerID,
            discoveryInfo: ["host": hostName],
            serviceType: NearbyService.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    /// Joiner side: look for hosts.
    @MainActor
    func startBrowsing(myName: String) {
        stop()
        isHosting = false
        let session = makeSession(name: myName)
        mcSession = session
        let browser = MCNearbyServiceBrowser(peer: session.myPeerID, serviceType: NearbyService.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        joinState = .browsing
    }

    @MainActor
    func join(_ host: NearbyHost) {
        guard let session = mcSession, let browser else { return }
        joinState = .connecting(host.name)
        browser.invitePeer(host.peerID, to: session, withContext: nil, timeout: 20)
    }

    /// Tear everything down (leaving the nearby screens without a game, or
    /// closing a finished nearby game).
    @MainActor
    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        mcSession?.disconnect()
        advertiser = nil
        browser = nil
        mcSession = nil
        isHosting = false
        roster = []
        foundHosts = []
        joinState = .idle
        receivedWelcome = nil
        slotAssignments = [:]
        activeWelcomes = [:]
        startedGame = nil
        lock.lock()
        records = [:]
        let waiting = pendingGets
        pendingGets = [:]
        hostPeer = nil
        lock.unlock()
        for (_, continuation) in waiting { continuation.resume(returning: [:]) }
    }

    /// Host: send every connected peer its seat. Called at start with the
    /// final roster; also re-sent automatically on reconnect.
    @MainActor
    func sendWelcomes(gameID: String, keyBase64URL: String, slots: [String: Int]) {
        guard let session = mcSession else { return }
        slotAssignments = slots
        startedGame = (gameID, keyBase64URL)
        for peer in roster {
            guard let slot = slots[peer.name] else { continue }
            let welcome = Packet.welcome(gameID: gameID, slot: slot, keyBase64URL: keyBase64URL)
            activeWelcomes[peer.peerID] = NearbyWelcome(gameID: gameID, slot: slot, keyBase64URL: keyBase64URL)
            send(welcome, to: [peer.peerID], via: session)
        }
    }

    /// The joiner consumed its welcome and opened the game.
    @MainActor
    func clearWelcome() {
        receivedWelcome = nil
    }

    // MARK: - Transport plumbing (called by MultipeerTransport)

    /// Host store, or the local mirror the host's own loops use.
    func storeLocal(id: String, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        if records[id] == nil { records[id] = body }
    }

    func fetchLocal(ids: [String]) -> [String: Data] {
        lock.lock()
        defer { lock.unlock() }
        var found: [String: Data] = [:]
        for id in ids {
            if let body = records[id] { found[id] = body }
        }
        return found
    }

    /// Peer → host put. Fire-and-forget on the reliable channel.
    func sendPut(id: String, body: Data) {
        lock.lock()
        let host = hostPeer
        let session = mcSession
        lock.unlock()
        guard let host, let session else { return }
        send(.put(id: id, body: body), to: [host], via: session)
    }

    /// Peer → host get, awaited. Times out to an empty result — the game
    /// loops poll, so a lost packet only costs one round-trip.
    func requestRecords(ids: [String]) async -> [String: Data] {
        lock.lock()
        let host = hostPeer
        let session = mcSession
        lock.unlock()
        guard let host, let session else { return [:] }
        let requestID = UUID()
        return await withCheckedContinuation { continuation in
            lock.lock()
            pendingGets[requestID] = continuation
            lock.unlock()
            send(.get(requestID: requestID, ids: ids), to: [host], via: session)
            Task {
                try? await Task.sleep(for: .seconds(4))
                self.lock.lock()
                let waiting = self.pendingGets.removeValue(forKey: requestID)
                self.lock.unlock()
                waiting?.resume(returning: [:])
            }
        }
    }

    private func send(_ packet: Packet, to peers: [MCPeerID], via session: MCSession) {
        guard !peers.isEmpty, let data = try? JSONEncoder().encode(packet) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }
}

// MARK: - MCSessionDelegate

extension NearbyService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if self.isHosting {
                    // Wait for the hello before showing them in the roster.
                    // A reconnecting player gets their seat straight back.
                    if let welcome = self.activeWelcomes[peerID], let mc = self.mcSession {
                        self.send(.welcome(gameID: welcome.gameID, slot: welcome.slot, keyBase64URL: welcome.keyBase64URL), to: [peerID], via: mc)
                    }
                } else {
                    self.lock.lock()
                    self.hostPeer = peerID
                    self.lock.unlock()
                    self.joinState = .connected(peerID.displayName)
                    // Introduce ourselves so the host's roster gets a name.
                    if let mc = self.mcSession {
                        self.send(.hello(name: mc.myPeerID.displayName, protocolVersion: AppProtocol.current), to: [peerID], via: mc)
                    }
                }
            case .notConnected:
                if self.isHosting {
                    self.roster.removeAll { $0.peerID == peerID }
                } else {
                    self.lock.lock()
                    let wasHost = self.hostPeer == peerID
                    if wasHost { self.hostPeer = nil }
                    self.lock.unlock()
                    if wasHost, case .connected = self.joinState {
                        self.joinState = .browsing
                    } else if case .connecting = self.joinState {
                        self.joinState = .browsing
                    }
                }
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let packet = try? JSONDecoder().decode(Packet.self, from: data) else { return }
        switch packet {
        case .put(let id, let body):
            storeLocal(id: id, body: body)
        case .get(let requestID, let ids):
            let found = fetchLocal(ids: ids)
            send(.records(requestID: requestID, found: found), to: [peerID], via: session)
        case .records(let requestID, let found):
            lock.lock()
            let waiting = pendingGets.removeValue(forKey: requestID)
            lock.unlock()
            waiting?.resume(returning: found)
        case .hello(let name, _):
            Task { @MainActor in
                guard self.isHosting else { return }
                self.roster.removeAll { $0.peerID == peerID }
                self.roster.append(NearbyPeer(peerID: peerID, name: name))
                // Mid-game rejoin after an app restart: same name, new
                // peer identity — hand their seat back.
                if let game = self.startedGame, let slot = self.slotAssignments[name], let mc = self.mcSession {
                    self.activeWelcomes[peerID] = NearbyWelcome(gameID: game.gameID, slot: slot, keyBase64URL: game.key)
                    self.send(.welcome(gameID: game.gameID, slot: slot, keyBase64URL: game.key), to: [peerID], via: mc)
                }
            }
        case .welcome(let gameID, let slot, let key):
            Task { @MainActor in
                guard !self.isHosting else { return }
                self.receivedWelcome = NearbyWelcome(gameID: gameID, slot: slot, keyBase64URL: key)
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser / Browser delegates

extension NearbyService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // The host's door is open to everyone in the room.
        invitationHandler(true, mcSession)
    }
}

extension NearbyService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let name = info?["host"] ?? peerID.displayName
        Task { @MainActor in
            guard !self.isHosting else { return }
            self.foundHosts.removeAll { $0.peerID == peerID }
            self.foundHosts.append(NearbyHost(peerID: peerID, name: name))
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.foundHosts.removeAll { $0.peerID == peerID }
        }
    }
}
