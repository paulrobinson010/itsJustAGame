import SwiftUI

struct CreateGameView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var roundsToWin = 3
    @State private var playerCount = 3
    @State private var names: [String]
    @State private var phones: [String?] = Array(repeating: nil, count: 8)
    @State private var pickerTarget: PickerTarget?

    private struct PickerTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

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
                                    pickerTarget = PickerTarget(index: index)
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
                    Text("Every player needs a name. Pick from contacts to fill the name and send their invite by iMessage straight from the lobby. Contacts never leave this phone.")
                }
            }
            .sheet(item: $pickerTarget) { target in
                ContactPickerView { contact in
                    names[target.index] = contact.firstName
                    phones[target.index] = contact.phone
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
}
