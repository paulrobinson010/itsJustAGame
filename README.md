# It's Just a Game

An iOS party game for friends and family. One person starts a game, sends
everyone a personal invite link, and the group plays a series of mini games.
A spinning wheel picks who chooses each round's game — the first mini game is
**Sense of Direction**.

Everything the game sends between devices is **end-to-end encrypted**.

## How it works

### Game flow

1. **Create** — the host picks how many rounds it takes to win, how many
   players, and their names. The app generates a personal invite link for
   every player except the host.
2. **Join** — players paste their link into the app (or just tap it — the
   app registers the `itsjustagame://` URL scheme).
3. **Lobby** — the host sees everyone join, then starts the game.
4. **Wheel** — a spinning wheel picks who chooses the round's mini game. The
   result is decided at random on the host device; the wheel animation just
   lands on it.
5. **Round** — a *game* is made of *rounds* (first to N rounds wins the
   game). Each round is one mini game. Within Sense of Direction, each
   *turn* is one target place; the turn winner gets a point, and the first
   player to 3 points takes the round.

### Sense of Direction

A place near the players is chosen (via MapKit search around the players'
locations, with a curated list of world landmarks as a fallback). Players see
the place name, then have 15 seconds to rotate an arrow on a compass dial to
point toward it. The device knows the true bearing from GPS but never shows
it. When everyone has locked in (or time runs out), all players see a map
with everyone's location, the target, and each player's guess drawn as a ray
— a perfect guess ends exactly on the target. Closest bearing wins the point.

There's also a **"Point with phone"** toggle on the dial that aligns the dial
with the real world using the compass, so you can physically point instead of
dragging. On-screen dragging is the default because colocated players could
copy each other's physical pointing.

### End-to-end encryption

- Creating a game generates a random 256-bit ChaCha20-Poly1305 key on the
  host device. The key travels **only inside the invite links** (in the URL
  fragment) and is stored locally on each device — it is never uploaded.
- Every message between devices is sealed with that key. CloudKit's public
  database is used purely as a dumb mailbox of ciphertext records with
  content-free IDs (random game ID + a structural suffix like `-h3` or
  `-r1-t2-ans4`). Apple can see that opaque blobs exist, but not names,
  locations, scores, or anything else.
- Anyone holding an invite link holds the key — the game is private to the
  people who were sent a link, so share the links privately.

### Architecture

- **Host-authoritative**: all randomness (wheel result, target locations)
  and all scoring happen on the starter's device (`HostEngine`). Other
  devices only publish their own input (join / choice / answer).
- **Replayable stream**: the host publishes a sequenced message stream
  (`h0, h1, h2…`). Every device — the host included — runs a `GameSession`
  that folds this stream into UI state. A player relaunching the app rebuilds
  the whole game by replaying from 0.
- **Swappable transport**: `GameTransport` is a two-method protocol
  (`put`/`get` by record ID). `CloudKitTransport` is the only implementation
  today; an Android-friendly backend later means re-implementing those two
  calls, nothing else. Fetch-by-ID means CloudKit needs **no custom indexes
  or schema setup** — the record type is created automatically on first save
  in the development environment.
- Sync is foreground polling (~1.5–2 s) for v1. Fine for a lobby-and-turns
  party game; push subscriptions can come later.

```
ItsJustAGame/
├── App/            App entry point + top-level model
├── Crypto/         ChaChaPoly sealing, key <-> base64url
├── Models/         GameConfig, players, host/player message types
├── Links/          itsjustagame://join/<gameID>/<slot>#<key>
├── Transport/      GameTransport protocol + CloudKitTransport
├── Engine/         HostEngine (authoritative) + GameSession (replay)
├── Location/       CoreLocation wrapper (GPS one-shots + compass heading)
├── Persistence/    Local store of joined games + their keys
├── Games/SenseOfDirection/
│   ├── DirectionMath, curated landmarks, MapKit LocationPicker
│   ├── DirectionTurnView (dial + countdown)
│   └── RevealView (results map)
└── Views/          Home, Create, Join, Lobby, Wheel, GameScreen
```

## Getting started

1. Open `ItsJustAGame.xcodeproj` in **Xcode 16 or later**.
2. In the target's *Signing & Capabilities* tab, select your team and change
   the bundle identifier to one in your namespace. The iCloud container is
   `iCloud.$(CFBundleIdentifier)`, so it follows the bundle ID automatically
   — Xcode will create the container on first build (paid Apple Developer
   account required).
3. Run on a real device (the compass and GPS don't exist in the simulator;
   the simulator works for UI with a simulated location).
4. Every player must be **signed in to iCloud** — writes to the CloudKit
   public database require an iCloud account.
5. To play: start a game on one device, share the links (Messages, etc.),
   paste/tap them on the other devices, and start from the lobby.

The first CloudKit save in a fresh container can take a moment while the
record type is created. If you later deploy to TestFlight/App Store, promote
the CloudKit schema from Development to Production in the CloudKit Console
first.

## Current limitations (v1 prototype)

- The **host device must stay in the app** for the whole game — it drives
  the rounds. Players can leave and rejoin freely (state replays), but a
  host relaunch mid-game can't resume yet (the lobby will say so).
- Timers assume device clocks are roughly in sync (they lean on the host's
  timestamps; NTP keeps modern phones within a second or two).
- Latency is polling-based (~1.5–2 s), which suits the turn cadence; CloudKit
  push subscriptions are the obvious upgrade.
- The reveal map shows every player's real location to the whole group —
  inherent to the game, encrypted in transit, but worth knowing.
- Timing values (15 s aim, reveal pauses, etc.) live in one place
  (`GameTiming`) so we can tune them once the prototype is in hand.

## Roadmap

- More mini games (the wheel/choice mechanic already supports them —
  add a case to `MiniGameType` and a view per phase).
- CloudKit push subscriptions instead of polling.
- Host resume mid-game (the message stream already makes this possible).
- Universal links (`https://…`) alongside the custom scheme — the key
  already rides in the URL fragment, which never reaches the server.
