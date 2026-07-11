import SwiftUI
import UIKit

struct JoinGameView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste your invite link", text: $linkText, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        if let text = UIPasteboard.general.string {
                            linkText = text
                        }
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    if let error = model.joinError {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Ask the game starter to send you your personal link. Tapping a link also opens the app directly.")
                    }
                }
            }
            .navigationTitle("Join a game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        model.join(text: linkText)
                        if model.activeGame != nil {
                            dismiss()
                        }
                    }
                    .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
