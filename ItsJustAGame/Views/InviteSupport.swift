import Contacts
import MessageUI
import SwiftUI

/// A contact as the game needs it. Read on-device only: the name goes into
/// the (encrypted) game config, the messaging address stays on the host's
/// phone purely to address the iMessage. iMessage reaches people by phone
/// number or by email (Apple ID), so either works as the address.
struct PickedContact: Identifiable, Hashable {
    let id: String
    let displayName: String
    let firstName: String
    /// Preferred iMessage address: mobile number, else any number, else email.
    let address: String?
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

/// Searchable contact list with frequent players pinned on top. In
/// multi-select mode rows toggle checkmarks and a toolbar button confirms.
struct ContactPickerView: View {
    var allowsMultiple = false
    var onPick: ([PickedContact]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [PickedContact] = []
    @State private var searchText = ""
    @State private var accessDenied = false
    @State private var loading = true
    /// Ordered selection for multi-select mode.
    @State private var selectedIDs: [String] = []

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
            .navigationTitle(allowsMultiple ? "Pick players" : "Pick a player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if allowsMultiple {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(selectedIDs.count)") {
                            confirmSelection()
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                }
            }
            .task { await load() }
        }
    }

    private func rows(_ list: [PickedContact]) -> some View {
        ForEach(list) { contact in
            Button {
                if allowsMultiple {
                    toggle(contact)
                } else {
                    RecentContacts.markPicked(contact.id)
                    onPick([contact])
                    dismiss()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName)
                            .foregroundStyle(.primary)
                        if let address = contact.address {
                            Text(address)
                                .font(Theme.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if contact.address == nil {
                        Text("no number or email")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                    }
                    if allowsMultiple {
                        Image(systemName: selectedIDs.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedIDs.contains(contact.id) ? Theme.cyan : Color.secondary)
                    }
                }
            }
        }
    }

    private func toggle(_ contact: PickedContact) {
        if let index = selectedIDs.firstIndex(of: contact.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(contact.id)
        }
    }

    private func confirmSelection() {
        let picked = selectedIDs.compactMap { id in
            contacts.first { $0.id == id }
        }
        for contact in picked {
            RecentContacts.markPicked(contact.id)
        }
        onPick(picked)
        dismiss()
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
            let keys = [
                CNContactGivenNameKey,
                CNContactFamilyNameKey,
                CNContactPhoneNumbersKey,
                CNContactEmailAddressesKey,
            ] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName
            var list: [PickedContact] = []
            try? store.enumerateContacts(with: request) { contact, _ in
                let first = contact.givenName.trimmingCharacters(in: .whitespaces)
                let full = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                guard !full.isEmpty else { return }
                let mobile = contact.phoneNumbers.first {
                    $0.label == CNLabelPhoneNumberMobile || $0.label == CNLabelPhoneNumberiPhone
                }
                let phone = (mobile ?? contact.phoneNumbers.first)?.value.stringValue
                let email = contact.emailAddresses.first.map { String($0.value) }
                list.append(PickedContact(
                    id: contact.identifier,
                    displayName: full,
                    firstName: first.isEmpty ? full : first,
                    address: phone ?? email
                ))
            }
            return list
        }.value
        contacts = loaded
        loading = false
    }
}

/// The "Add players from contacts" sheet: consent first (once), then the
/// picker — both faces of ONE presentation, switched by plain view state.
/// Programmatic sheet-to-sheet transitions kept stranding the button dead
/// after the first use, so there are none: the parent presents a single
/// boolean-driven sheet and never touches it again.
struct AddPlayersFlow: View {
    var onPick: ([PickedContact]) -> Void

    @State private var consented = ContactsConsentView.hasConsented

    var body: some View {
        if consented {
            ContactPickerView(allowsMultiple: true, onPick: onPick)
        } else {
            ContactsConsentView {
                withAnimation(.snappy) { consented = true }
            }
        }
    }
}

/// Explicit consent before the contact picker ever opens (App Review
/// 5.1.2): spells out exactly what happens to a picked contact — the
/// first name is shared with the game group end-to-end encrypted, the
/// number/email never leaves the phone — and asks the user to agree.
/// Shown once; the choice is remembered.
struct ContactsConsentView: View {
    var onConsent: () -> Void
    @Environment(\.dismiss) private var dismiss

    static let consentKey = "contactsConsentGiven"

    static var hasConsented: Bool {
        UserDefaults.standard.bool(forKey: consentKey)
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "person.2.badge.key.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.cyan)
            Text("Before you pick players")
                .font(Theme.display(26))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                Label {
                    Text("The **first name** of each player you pick is shared with the people in your game — end-to-end encrypted via iCloud, readable only by them.")
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.cyan)
                }
                Label {
                    Text("**Phone numbers and emails never leave this phone.** They're used only to address the iMessage invites you send yourself.")
                } icon: {
                    Image(systemName: "iphone").foregroundStyle(Theme.cyan)
                }
                Label {
                    Text("We run no servers and **collect nothing** — there's no account, no analytics, no ads.")
                } icon: {
                    Image(systemName: "eye.slash.fill").foregroundStyle(Theme.cyan)
                }
            }
            .font(Theme.subheadline)
            .padding(.horizontal, 28)
            Spacer()
            Button {
                UserDefaults.standard.set(true, forKey: ContactsConsentView.consentKey)
                // No dismiss() here: AddPlayersFlow flips to the picker
                // inside the same, still-presented sheet.
                onConsent()
            } label: {
                Text("I agree — choose from contacts")
                    .frame(maxWidth: 300)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button {
                dismiss()
            } label: {
                Text("No thanks — I'll type names instead")
                    .frame(maxWidth: 300)
            }
            .buttonStyle(QuietButtonStyle())
            .padding(.bottom, 20)
        }
        .background(Theme.background)
    }
}

/// The system share sheet, presented as a real sheet rather than
/// SwiftUI's ShareLink popover — on iPad the popover could end up
/// clipped or hidden (App Review, twice); a sheet is unmissable on
/// every device.
struct ActivityShareView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
