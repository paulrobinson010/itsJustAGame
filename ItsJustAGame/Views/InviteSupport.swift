import Contacts
import MessageUI
import SwiftUI

/// A contact as the game needs it. Read on-device only: the name goes into
/// the (encrypted) game config, the phone number stays on the host's phone
/// purely to address the iMessage.
struct PickedContact: Identifiable, Hashable {
    let id: String
    let displayName: String
    let firstName: String
    let phone: String?
}

/// iOS offers no API for the Phone app's Favourites, so "favourites" here
/// means the people you've picked before in this app, most recent first.
enum RecentContacts {
    private static let key = "recentContactIDs"

    static func ids() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func markPicked(_ id: String) {
        var list = ids().filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(8)), forKey: key)
    }
}

/// Searchable contact list with frequent players pinned on top.
struct ContactPickerView: View {
    var onPick: (PickedContact) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [PickedContact] = []
    @State private var searchText = ""
    @State private var accessDenied = false
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if accessDenied {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Contacts access is off")
                            .font(Theme.headline)
                        Text("Allow access in Settings → Privacy → Contacts to pick players. You can still type names by hand.")
                            .font(Theme.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else if loading {
                    ProgressView()
                } else {
                    List {
                        let frequent = frequentContacts
                        if searchText.isEmpty && !frequent.isEmpty {
                            Section("Frequent players") {
                                rows(frequent)
                            }
                        }
                        Section(searchText.isEmpty ? "All contacts" : "Results") {
                            rows(filteredContacts)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search contacts")
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Pick a player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func rows(_ list: [PickedContact]) -> some View {
        ForEach(list) { contact in
            Button {
                RecentContacts.markPicked(contact.id)
                onPick(contact)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName)
                            .foregroundStyle(.primary)
                        if let phone = contact.phone {
                            Text(phone)
                                .font(Theme.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if contact.phone == nil {
                        Text("no number")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var frequentContacts: [PickedContact] {
        RecentContacts.ids().compactMap { id in
            contacts.first { $0.id == id }
        }
    }

    private var filteredContacts: [PickedContact] {
        guard !searchText.isEmpty else { return contacts }
        return contacts.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    private func load() async {
        let store = CNContactStore()
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        guard granted else {
            accessDenied = true
            loading = false
            return
        }
        let loaded = await Task.detached { () -> [PickedContact] in
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName
            var list: [PickedContact] = []
            try? store.enumerateContacts(with: request) { contact, _ in
                let first = contact.givenName.trimmingCharacters(in: .whitespaces)
                let full = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                guard !full.isEmpty else { return }
                list.append(PickedContact(
                    id: contact.identifier,
                    displayName: full,
                    firstName: first.isEmpty ? full : first,
                    phone: contact.phoneNumbers.first?.value.stringValue
                ))
            }
            return list
        }.value
        contacts = loaded
        loading = false
    }
}

/// The system iMessage composer, pre-addressed with the invite. iOS
/// requires the sender to tap Send themselves — no app can send silently.
struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    @Environment(\.dismiss) private var dismiss

    static var canSend: Bool {
        MFMessageComposeViewController.canSendText()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let parent: MessageComposeView

        init(_ parent: MessageComposeView) {
            self.parent = parent
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.dismiss()
        }
    }
}
