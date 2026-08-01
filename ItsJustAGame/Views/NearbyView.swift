import SwiftUI

/// Nearby (no-internet) play: host or join a game over Bluetooth and
/// peer-to-peer Wi-Fi — made for planes, campsites and anywhere else the
/// internet isn't. `onDone` closes the whole sheet once a game opens.
struct NearbyView: View {
    let model: AppModel
    var onDone: () -> Void

    @AppStorage("myName") private var myName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Your name", text: $myName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("You")
                } footer: {
                    Text("Nearby play uses Bluetooth and peer-to-peer Wi-Fi — no internet, no iCloud. On a plane, pop out of airplane mode's radio bans by switching Bluetooth and Wi-Fi back on in Control Centre.")
                }

                Section {
                    NavigationLink {
                        NearbyHostView(model: model, myName: trimmedName, onDone: onDone)
                    } label: {
                        Label("Host the game", systemImage: "antenna.radiowaves.left.and.right")
                            .font(Theme.headline)
                    }
                    .disabled(trimmedName.isEmpty)
                    NavigationLink {
                        NearbyJoinView(model: model, myName: trimmedName, onDone: onDone)
                    } label: {
                        Label("Join a game nearby", systemImage: "person.wave.2.fill")
                            .font(Theme.headline)
                    }
                    .disabled(trimmedName.isEmpty)
                } footer: {
                    Text(trimmedName.isEmpty
                         ? "Enter your name first — it's how the others see you."
                         : "One person hosts; everyone else joins. Map games sit out (they need the internet); the other games all work.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Play nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var trimmedName: String {
        myName.trimmingCharacters(in: .whitespaces)
    }
}

/// The host's nearby lobby: advertising starts on arrival, players appear
/// as they connect, Simplify hides behind the wand, and Start deals the
/// seats and opens the game.
struct NearbyHostView: View {
    let model: AppModel
    let myName: String
    var onDone: () -> Void

    @State private var roundsToWin: Int
    @State private var myAssist: AssistLevel?
    /// Keyed by player name (names are what survive reconnects).
    @State private var assists: [String: AssistLevel] = [:]
    @State private var started = false
    @State private var waitingLong = false

    private var service: NearbyService { NearbyService.shared }

    init(model: AppModel, myName: String, onDone: @escaping () -> Void) {
        self.model = model
        self.myName = myName
        self.onDone = onDone
        let remembered = UserDefaults.standard.integer(forKey: "lastRoundsToWin")
        _roundsToWin = State(initialValue: (1...10).contains(remembered) ? remembered : 3)
    }

    var body: some View {
        List {
            Section("You — hosting") {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Theme.cyan)
                        .symbolEffect(.variableColor.iterative, options: .repeating, value: started)
                    Text(myName)
                    Spacer()
                    assistMenu(binding(forHost: true, name: myName))
                }
            }

            Section {
                if service.roster.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Waiting for players…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(service.roster) { peer in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(peer.name)
                            Spacer()
                            assistMenu(binding(forHost: false, name: peer.name))
                        }
                    }
                }
            } header: {
                Text("Joined — \(service.roster.count + 1) of 8")
            } footer: {
                if waitingLong && service.roster.isEmpty {
                    Text("Nobody yet? Everyone needs Bluetooth and Wi-Fi on, and this app allowed under Settings → Privacy & Security → Local Network. They should see \"\(myName)'s game\" in their list.")
                } else {
                    Text("Tell everyone: Play nearby → Join a game nearby → tap your name. The wand quietly makes games easier for that player.")
                }
            }

            Section("Rules") {
                Stepper("First to \(roundsToWin) round\(roundsToWin == 1 ? "" : "s") wins", value: $roundsToWin, in: 1...10)
            }

            Section {
                Button {
                    start()
                } label: {
                    Label(
                        service.roster.isEmpty
                            ? "Waiting for players to join"
                            : "Start game for \(service.roster.count + 1)",
                        systemImage: "play.circle.fill"
                    )
                    .font(Theme.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyan)
                .disabled(service.roster.isEmpty || started)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Nearby lobby")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            service.startHosting(hostName: myName)
            try? await Task.sleep(for: .seconds(10))
            waitingLong = true
        }
        .onDisappear {
            // Backed out without starting — close the doors. (When the
            // game starts, the session must live on underneath it.)
            if !started {
                service.stop()
            }
        }
    }

    private func start() {
        started = true
        UserDefaults.standard.set(roundsToWin, forKey: "lastRoundsToWin")
        let peers = Array(service.roster.prefix(7))
        var slotAssists: [Int: AssistLevel] = [:]
        slotAssists[1] = myAssist
        for (index, peer) in peers.enumerated() {
            slotAssists[index + 2] = assists[peer.name]
        }
        // Close this sheet BEFORE the game's full-screen cover goes up —
        // presenting one while the other is still animating away is how
        // covers silently fail to appear.
        onDone()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            model.hostNearbyGame(
                roundsToWin: roundsToWin,
                hostName: myName,
                peerNames: peers.map(\.name),
                assists: slotAssists.compactMapValues { $0 }
            )
        }
    }

    private func binding(forHost: Bool, name: String) -> Binding<AssistLevel?> {
        if forHost {
            return Binding(get: { myAssist }, set: { myAssist = $0 })
        }
        return Binding(get: { assists[name] }, set: { assists[name] = $0 })
    }

    private func assistMenu(_ level: Binding<AssistLevel?>) -> some View {
        Menu {
            Button {
                level.wrappedValue = nil
            } label: {
                if level.wrappedValue == nil {
                    Label("Simplify off", systemImage: "checkmark")
                } else {
                    Text("Simplify off")
                }
            }
            ForEach(AssistLevel.allCases, id: \.self) { choice in
                Button {
                    level.wrappedValue = choice
                } label: {
                    if level.wrappedValue == choice {
                        Label(choice.displayName, systemImage: "checkmark")
                    } else {
                        Text(choice.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: level.wrappedValue == nil ? "wand.and.stars.inverse" : "wand.and.stars")
                .foregroundStyle(level.wrappedValue == nil ? Color.secondary : Theme.magenta)
        }
        .buttonStyle(.borderless)
    }
}

/// Shown over a nearby game when the host has gone for good — they either
/// left deliberately or never came back. A nearby game can't outlive its
/// host: their phone holds the only copy of the game's records.
struct HostLeftOverlay: View {
    let hostName: String
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.magenta)
                Text("\(hostName) has left")
                    .font(Theme.display(28))
                    .multilineTextAlignment(.center)
                Text("The game ran on their phone, so it ends here. Nothing's lost — start another whenever you're ready.")
                    .font(Theme.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button {
                    onClose()
                } label: {
                    Text("Back to home")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            }
            .padding(.vertical, 40)
        }
        .transition(.opacity)
    }
}

/// The joiner's side: browse for hosts, tap one, then wait — the game
/// opens by itself the moment the host starts it.
struct NearbyJoinView: View {
    let model: AppModel
    let myName: String
    var onDone: () -> Void

    @State private var opened = false
    /// Set once we've been looking a while with nothing to show for it —
    /// almost always the local network prompt having been declined.
    @State private var searchingLong = false

    private var service: NearbyService { NearbyService.shared }

    var body: some View {
        List {
            if let note = service.note {
                Section {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.caption)
                        .foregroundStyle(.orange)
                }
            }
            switch service.joinState {
            case .connected(let hostName):
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected to \(hostName)")
                            Text("The game starts when \(hostName) taps Start — stay on this screen.")
                                .font(Theme.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            default:
                Section {
                    if service.foundHosts.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Looking for a host nearby…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(service.foundHosts) { host in
                            Button {
                                service.join(host)
                            } label: {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundStyle(Theme.cyan)
                                    Text("\(host.name)'s game")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if case .connecting(let target) = service.joinState, target == host.name {
                                        ProgressView()
                                    } else {
                                        Text("Join").foregroundStyle(Theme.cyan)
                                    }
                                }
                            }
                        }
                    }
                } footer: {
                    if searchingLong && service.foundHosts.isEmpty {
                        Text("Still nothing? Check the host has tapped \"Host the game\", that Bluetooth and Wi-Fi are on for both phones, and that this app is allowed under Settings → Privacy & Security → Local Network.")
                    } else {
                        Text("Ask someone to host first: Play nearby → Host the game. Keep Bluetooth and Wi-Fi switched on.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Join nearby")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            service.startBrowsing(myName: myName)
            try? await Task.sleep(for: .seconds(8))
            searchingLong = true
        }
        .onChange(of: service.receivedWelcome) { _, welcome in
            guard let welcome, !opened else { return }
            opened = true
            // Sheet away first, then the game's cover — see NearbyHostView.
            onDone()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.4))
                model.joinNearbyGame(welcome)
            }
        }
        .onDisappear {
            if !opened {
                service.stop()
            }
        }
    }
}
