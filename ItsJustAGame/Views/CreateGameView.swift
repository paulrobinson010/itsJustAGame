import SwiftUI

struct CreateGameView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var roundsToWin: Int
    @State private var playerCount = 3
    @State private var names: [String]
    @State private var phones: [String?] = Array(repeating: nil, count: 8)
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
                        HStack {
                            TextField(index == 0 ? "You" : "Player \(index + 1) name", text: $names[index])
                                .textInputAutocapitalization(.words)
                            if index > 0 {
                                if phones[index] != nil {
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
                    }
                } header: {
                    Text("Players")
                } footer: {
                    Text("Every player needs a name. Pick from contacts to fill names and send invites by iMessage straight from the lobby. Contacts never leave this phone.")
                }
            }
            .sheet(item: $pickerMode) { mode in
                switch mode {
                case .single(let index):
                    ContactPickerView { picked in
                        guard let contact = picked.first else { return }
                        names[index] = contact.firstName
                        phones[index] = contact.phone
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
                            inviteePhones: inviteePhones
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

    private var inviteePhones: [Int: String] {
        var result: [Int: String] = [:]
        for index in 1..<playerCount {
            if let phone = phones[index] {
                result[index + 1] = phone
            }
        }
        return result
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
            phones[offset + 1] = contact.phone
        }
    }

    private func applyLastGame(_ last: SavedGame) {
        guard let config = last.hostConfig else { return }
        let others = config.players.filter { $0.slot != 1 }.prefix(7)
        guard !others.isEmpty else { return }
        playerCount = others.count + 1
        for (offset, player) in others.enumerated() {
            names[offset + 1] = player.name
            phones[offset + 1] = last.inviteePhones?[player.slot]
        }
        roundsToWin = config.roundsToWin
    }
}
