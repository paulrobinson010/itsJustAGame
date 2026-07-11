import CloudKit
import SwiftUI

struct HomeView: View {
    @Bindable var model: AppModel
    @AppStorage("myName") private var myName = ""
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var accountWarning: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 130)
                            .shadow(color: Theme.cyan.opacity(0.25), radius: 24)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("Your name", text: $myName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("You")
                } footer: {
                    Text("Remembered for the games you create and join.")
                }

                Section {
                    Button {
                        showCreate = true
                    } label: {
                        Label("Start a new game", systemImage: "plus.circle.fill")
                    }
                    Button {
                        showJoin = true
                    } label: {
                        Label("Join with a link", systemImage: "link")
                    }
                }

                if !model.store.games.isEmpty {
                    Section("Your games") {
                        ForEach(model.store.games) { game in
                            Button {
                                model.activeGame = game
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(game.title)
                                        .foregroundStyle(.primary)
                                    Text("\(game.isHost ? "Host" : "Player \(game.mySlot)") · \(game.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            let doomed = indexSet.map { model.store.games[$0] }
                            for game in doomed {
                                model.store.remove(game)
                            }
                        }
                    }
                }

                if let accountWarning {
                    Section {
                        Label(accountWarning, systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("It's Just a Game")
            .sheet(isPresented: $showCreate) {
                CreateGameView(model: model, myName: myName)
            }
            .sheet(isPresented: $showJoin) {
                JoinGameView(model: model)
            }
            .fullScreenCover(item: $model.activeGame) { game in
                // id forces a fresh screen (and fresh session) per game so
                // switching games mid-cover — e.g. into a rematch — works.
                GameScreen(saved: game, model: model)
                    .id(game.gameID)
            }
            .task {
                LocationService.shared.requestPermission()
                let status = await CloudKitTransport.accountStatus()
                if status != .available {
                    accountWarning = "Sign in to iCloud in Settings to play — the game passes its encrypted messages through iCloud."
                }
            }
        }
    }
}
