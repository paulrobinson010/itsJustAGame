import CloudKit
import SwiftUI

struct HomeView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("myName") private var myName = ""
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var accountWarning: String?
    #if targetEnvironment(simulator)
    @State private var showDemoTour = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .shadow(color: Theme.cyan.opacity(0.3), radius: 24)
                        Text("IT'S JUST A GAME")
                            .font(Theme.display(27))
                            .kerning(2.5)
                            .foregroundStyle(Theme.brandGradient)
                            .shadow(color: Theme.cyan.opacity(0.35), radius: 14)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
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
                                    if let summary = game.summary {
                                        Text("🏆 \(summary.name(summary.winner)) won · \(game.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\(game.isHost ? "Host" : "Player \(game.mySlot)") · \(game.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
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

                #if targetEnvironment(simulator)
                Section {
                    Button {
                        showDemoTour = true
                    } label: {
                        Label("Screenshot tour", systemImage: "camera.viewfinder")
                    }
                } header: {
                    Text("Simulator only")
                } footer: {
                    Text("Steps through every game with demo data, ~2s per screen. Tap to pause, swipe for next/previous, long-press to exit.")
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
            #if targetEnvironment(simulator)
            .fullScreenCover(isPresented: $showDemoTour) {
                DemoTourView()
            }
            #endif
            .task {
                LocationService.shared.requestPermission()
                let status = await CloudKitTransport.accountStatus()
                if status != .available {
                    accountWarning = "Sign in to iCloud in Settings to play — the game passes its encrypted messages through iCloud."
                }
                await model.discoverRematches()
            }
            .onChange(of: scenePhase) { _, phase in
                // Someone may have tapped "Play again" while this phone was
                // in a pocket — look for rematches on every return.
                if phase == .active {
                    Task { await model.discoverRematches() }
                }
            }
        }
    }
}
