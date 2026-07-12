import SwiftUI

struct CreateGameView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var roundsToWin: Int
    @State private var playerCount = 3
    @State private var names: [String]
    @State private var addresses: [String?] = Array(repeating: nil, count: 8)
    @State private var assists: [AssistLevel?] = Array(repeating: nil, count: 8)
    @State private var pickerMode: PickerMode?

    private enum PickerMode: Identifiable {
        case single(Int)
        case multiple

        var id: Int {
            if case .single(let index) = self { return index }
            return -1
        }
    }

    init(model: AppModel, myName: String) {
        self.model = model
        var initial = Array(repeating: "", count: 8)
        initial[0] = myName
        _names = State(initialValue: initial)
        let remembered = UserDefaults.standard.integer(forKey: "lastRoundsToWin")
        _roundsToWin = State(initialValue: (1...10).contains(remembered) ? remembered : 3)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rules") {
                    Stepper("Rounds to win: \(roundsToWin)", value: $roundsToWin, in: 1...10)
                    Stepper("Players: \(playerCount)", value: $playerCount, in: 2...8)
                }
                Section {
                    Button {
                        pickerMode = .multiple
                    } label: {
                        Label("Pick players from contacts", systemImage: "person.2.fill")
                    }
                    if let last = lastHostedGame {
                        Button {
                            applyLastGame(last)
                        } label: {
                            Label("Same players as last game", systemImage: "arrow.counterclockwise")
                        }
                    }
                    ForEach(0..<playerCount, id: \.self) { index in
                        VStack(spacing: 8) {
                            HStack {
                                TextField(index == 0 ? "You" : "Player \(index + 1) name", text: $names[index])
                                    .textInputAutocapitalization(.words)
                                if index > 0 {
                                    if addresses[index] != nil {
                                        Image(systemName: "message.fill")
                                            .font(.caption)
                                            .foregroundStyle(Theme.cyan)
                                    }
                                    Button {
                                        pickerMode = .single(index)
                                    } label: {
                                        Image(systemName: "person.crop.circle.badge.plus")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            HStack {
                                Toggle(isOn: simplifyBinding(index)) {
                                    Label("Simplify", systemImage: "wand.and.stars")
                                        .font(Theme.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                if assists[index] != nil {
                                    Picker("", selection: levelBinding(index)) {
                                        ForEach(AssistLevel.allCases, id: \.self) { level in
                                            Text(level.displayName).tag(level)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                }
                            }
                        }
                    }
                } header: {
                    Text("Players")
                } footer: {
                    Text("Every player needs a name. Pick from contacts to fill names and send invites by iMessage straight from the lobby. Contacts never leave this phone. Simplify quietly makes every mini game easier for that player — nothing in the game gives it away.")
                }
            }
            .sheet(item: $pickerMode) { mode in
                switch mode {
                case .single(let index):
                    ContactPickerView { picked in
                        guard let contact = picked.first else { return }
                        names[index] = contact.firstName
                        addresses[index] = contact.address
                    }
                case .multiple:
                    ContactPickerView(allowsMultiple: true) { picked in
                        applyPickedContacts(picked)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("New game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        UserDefaults.standard.set(roundsToWin, forKey: "lastRoundsToWin")
                        model.createGame(
                            roundsToWin: roundsToWin,
                            playerNames: trimmedNames,
                            inviteeAddresses: inviteeAddresses,
                            assists: chosenAssists
                        )
                        dismiss()
                    }
                    .disabled(!allPlayersNamed)
                }
            }
        }
    }

    private var trimmedNames: [String] {
        (0..<playerCount).map { names[$0].trimmingCharacters(in: .whitespaces) }
    }

    private var allPlayersNamed: Bool {
        trimmedNames.allSatisfy { !$0.isEmpty }
    }

    private var inviteeAddresses: [Int: String] {
        var result: [Int: String] = [:]
        for index in 1..<playerCount {
            if let phone = addresses[index] {
                result[index + 1] = phone
            }
        }
        return result
    }

    private var chosenAssists: [Int: AssistLevel] {
        var result: [Int: AssistLevel] = [:]
        for index in 0..<playerCount {
            if let level = assists[index] {
                result[index + 1] = level
            }
        }
        return result
    }

    private func simplifyBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { assists[index] != nil },
            set: { assists[index] = $0 ? .little : nil }
        )
    }

    private func levelBinding(_ index: Int) -> Binding<AssistLevel> {
        Binding(
            get: { assists[index] ?? .little },
            set: { assists[index] = $0 }
        )
    }

    private var lastHostedGame: SavedGame? {
        model.store.games.first { $0.isHost && $0.hostConfig != nil }
    }

    /// Fill the roster from a multi-select: one row per contact, in the
    /// order they were ticked.
    private func applyPickedContacts(_ picked: [PickedContact]) {
        let capped = picked.prefix(7)
        guard !capped.isEmpty else { return }
        playerCount = capped.count + 1
        for (offset, contact) in capped.enumerated() {
            names[offset + 1] = contact.firstName
            addresses[offset + 1] = contact.address
        }
    }

    private func applyLastGame(_ last: SavedGame) {
        guard let config = last.hostConfig else { return }
        let others = config.players.filter { $0.slot != 1 }.prefix(7)
        guard !others.isEmpty else { return }
        playerCount = others.count + 1
        assists[0] = config.player(1)?.assist
        for (offset, player) in others.enumerated() {
            names[offset + 1] = player.name
            addresses[offset + 1] = last.inviteeAddresses?[player.slot]
            assists[offset + 1] = player.assist
        }
        roundsToWin = config.roundsToWin
    }
}
