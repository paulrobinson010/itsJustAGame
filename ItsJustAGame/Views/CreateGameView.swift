import SwiftUI

/// Creating a game is two decisions: who's playing, and how many rounds.
/// The roster grows as players are added — from contacts (one tap, brings
/// the number for iMessage invites) or by typing a name — no player-count
/// stepper, no empty slots to fill.
struct CreateGameView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var roundsToWin: Int
    @State private var myName: String
    @State private var myAssist: AssistLevel?
    @State private var guests: [Guest] = []
    @State private var typedName = ""
    @State private var showContactPicker = false

    /// Everyone playing apart from you.
    struct Guest: Identifiable, Hashable {
        let id = UUID()
        var name: String
        /// Number or email for the iMessage invite (from contacts only).
        var address: String?
        var assist: AssistLevel?
    }

    private static let maxPlayers = 8

    init(model: AppModel, myName: String) {
        self.model = model
        _myName = State(initialValue: myName)
        let remembered = UserDefaults.standard.integer(forKey: "lastRoundsToWin")
        _roundsToWin = State(initialValue: (1...10).contains(remembered) ? remembered : 3)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showContactPicker = true
                    } label: {
                        Label("Add players from contacts", systemImage: "person.2.fill")
                            .font(Theme.headline)
                    }
                    .disabled(guests.count >= CreateGameView.maxPlayers - 1)
                    if let last = lastHostedGame {
                        Button {
                            applyLastGame(last)
                        } label: {
                            Label("Same players as last game", systemImage: "arrow.counterclockwise")
                        }
                    }
                } header: {
                    Text("Who's playing?")
                } footer: {
                    Text("Picking from contacts also grabs their number, so you can invite them by iMessage with one tap. Contacts never leave this phone.")
                }

                Section {
                    HStack {
                        TextField("Your name", text: $myName)
                            .textInputAutocapitalization(.words)
                        Spacer()
                        Text("You").font(Theme.caption).foregroundStyle(.secondary)
                        assistMenu($myAssist)
                    }
                    ForEach($guests) { $guest in
                        HStack {
                            TextField("Name", text: $guest.name)
                                .textInputAutocapitalization(.words)
                            Spacer()
                            if guest.address != nil {
                                Image(systemName: "message.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.cyan)
                            }
                            assistMenu($guest.assist)
                        }
                    }
                    .onDelete { guests.remove(atOffsets: $0) }
                    if guests.count < CreateGameView.maxPlayers - 1 {
                        HStack {
                            TextField("Add a player by name", text: $typedName)
                                .textInputAutocapitalization(.words)
                                .onSubmit(addTypedName)
                            Button {
                                addTypedName()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Theme.cyan)
                            }
                            .buttonStyle(.borderless)
                            .disabled(typedName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                } header: {
                    Text("Players — \(guests.count + 1) of \(CreateGameView.maxPlayers)")
                } footer: {
                    Text("Swipe a player to remove them. The wand quietly makes every mini game easier for that player — nothing on screen gives it away.")
                }

                Section("Rules") {
                    Stepper("First to \(roundsToWin) round\(roundsToWin == 1 ? "" : "s") wins", value: $roundsToWin, in: 1...10)
                }

                Section {
                    Button {
                        create()
                    } label: {
                        Label(
                            guests.isEmpty
                                ? "Add at least one player"
                                : "Create game for \(guests.count + 1)",
                            systemImage: "play.circle.fill"
                        )
                        .font(Theme.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cyan)
                    .disabled(!canCreate)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Next you'll get the lobby, where each player gets their own invite link.")
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerView(allowsMultiple: true) { picked in
                    addPickedContacts(picked)
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
            }
        }
    }

    /// Off / a little / a big help / basically cheating, in one compact menu.
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

    private var trimmedMyName: String {
        myName.trimmingCharacters(in: .whitespaces)
    }

    private var canCreate: Bool {
        !trimmedMyName.isEmpty
            && !guests.isEmpty
            && guests.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func addTypedName() {
        let name = typedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, guests.count < CreateGameView.maxPlayers - 1 else { return }
        guests.append(Guest(name: name))
        typedName = ""
    }

    private func addPickedContacts(_ picked: [PickedContact]) {
        for contact in picked {
            guard guests.count < CreateGameView.maxPlayers - 1 else { break }
            guests.append(Guest(name: contact.firstName, address: contact.address))
        }
    }

    private var lastHostedGame: SavedGame? {
        model.store.games.first { $0.isHost && $0.hostConfig != nil }
    }

    private func applyLastGame(_ last: SavedGame) {
        guard let config = last.hostConfig else { return }
        let others = config.players.filter { $0.slot != 1 }.prefix(CreateGameView.maxPlayers - 1)
        guard !others.isEmpty else { return }
        myAssist = config.player(1)?.assist
        guests = others.map { player in
            Guest(
                name: player.name,
                address: last.inviteeAddresses?[player.slot],
                assist: player.assist
            )
        }
        roundsToWin = config.roundsToWin
    }

    private func create() {
        UserDefaults.standard.set(roundsToWin, forKey: "lastRoundsToWin")
        var addresses: [Int: String] = [:]
        var assists: [Int: AssistLevel] = [:]
        assists[1] = myAssist
        for (offset, guest) in guests.enumerated() {
            addresses[offset + 2] = guest.address
            assists[offset + 2] = guest.assist
        }
        model.createGame(
            roundsToWin: roundsToWin,
            playerNames: [trimmedMyName] + guests.map { $0.name.trimmingCharacters(in: .whitespaces) },
            inviteeAddresses: addresses,
            assists: assists
        )
        dismiss()
    }
}
