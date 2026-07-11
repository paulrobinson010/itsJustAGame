import SwiftUI

struct CreateGameView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var roundsToWin = 3
    @State private var playerCount = 3
    @State private var names: [String]

    init(model: AppModel, myName: String) {
        self.model = model
        var initial = Array(repeating: "", count: 8)
        initial[0] = myName
        _names = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rules") {
                    Stepper("Rounds to win: \(roundsToWin)", value: $roundsToWin, in: 1...10)
                    Stepper("Players: \(playerCount)", value: $playerCount, in: 2...8)
                }
                Section {
                    ForEach(0..<playerCount, id: \.self) { index in
                        TextField(index == 0 ? "You" : "Player \(index + 1) name", text: $names[index])
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    Text("Players")
                } footer: {
                    Text("Every player needs a name. You are player 1 — everyone else gets their own invite link to send from the lobby.")
                }
            }
            .navigationTitle("New game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        model.createGame(roundsToWin: roundsToWin, playerNames: trimmedNames)
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
}
