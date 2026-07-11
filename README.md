# It's Just a Game

An iOS party game for friends and family. One person starts a game, sends
everyone a personal invite link, and the group plays a series of mini games.
A spinning wheel picks who chooses each round's game — the first mini game is
**Sense of Direction**.

Everything the game sends between devices is **end-to-end encrypted**.

## How it works

### Game flow

1. **Create** — the host picks how many rounds it takes to win, how many
   players, and their names (every player must be named). The app generates
   a personal invite link for every player except the host, to send by
   iMessage, WhatsApp, etc.
2. **Join** — players paste their invite message into the app (or tap the
   link — the app registers the `itsjustagame://` URL scheme). A joiner is
   greeted with "Welcome ⟨their name⟩ to ⟨host⟩'s game" before entering the
   lobby. Note: some messaging apps don't make custom-scheme links tappable,
   which is why the share message says "copy this whole message and paste it
   in the app" — the app finds the link inside the pasted text. Universal
   links (`https://…`) are the eventual fix.
3. **Lobby** — the host sees everyone join, then starts the game.
4. **Wheel** — a spinning wheel picks who chooses the round's mini game. The
   result is decided at random on the host device; the wheel animation just
   lands on it. Each mini game declares a minimum player count and is only
   offered when enough players have joined (Sense of Direction: 2) — the
   host enforces this, and a game can't start at all below the smallest
   minimum.
5. **Round** — a *game* is made of *rounds* (first to N rounds wins the
   game). Each round is one mini game. Within Sense of Direction, each
   *turn* is one target place; the turn winner gets a point, and the first
   player to 3 points takes the round.
6. **Ties share** — when several players win a point or a round together,
   they all score. If several players reach the winning round count at the
   same moment, a tie-breaker wheel of just those players spins and the
   overall winner is decided totally at random (rolled on the host device,
   like all randomness).

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

### Hide & Seek

Everyone secretly picks a hiding square on a 5×5 grid within 15 seconds
(no pick → a random square is assigned). The host then shuffles all players
into a run order, and in that order players take turns searching any square
that hasn't been searched yet — each search reveals every player hiding
there. Being found knocks you out of hiding but not out of seeking: everyone
keeps taking their seek turns. The last player left hidden wins the round
(if the final search reveals the last several hiders at once, the round goes
to one of them at random). A seeker who doesn't pick in time has a random
square searched for them, so the game always moves and always terminates.
If the final search reveals the last several hiders at once they were all
"found last" and share the round.

### Higher or Lower

A playing card is revealed (drawn in-app; ace is low). Everyone still
standing calls the next card **higher** (cyan) or **lower** (magenta)
within 10 seconds — wrong calls are eliminated, and a tied rank eliminates
nobody. Last player standing wins the match and scores a point; if the
final survivors all fall on the same card they were all "last to be
eliminated" and each scores. First to 3 points wins the round (several can
get there together and all take the round). A silent player gets a random
call rather than auto-elimination, so a network blip can't knock anyone
out. The host deals from a real shuffled 52-card deck, reshuffling when it
runs dry.

### Repeat After Me

A Simon-style memory duel on a 2×2 pad of cyan, magenta, lime and amber.
The pads flash a sequence (starting at 3, growing by one each turn — every
device flashes in step off the shared start timestamp); everyone alive
then taps it back from memory before the deadline. One wrong pad, a short
answer, or no answer eliminates you — this is a skill test, so unlike
Higher or Lower there is no random-mercy fallback for silence. Last player
standing takes the point; if everyone left fails the same sequence they
all score. First to 3 points wins the round, ties share, and the
game-level tie-break wheel applies as everywhere else.

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

## Design language

Very simple, but it should look expensive. The rules live in
`Views/Theme.swift` and every screen (and every future mini game) must pull
from them:

- **Dark, always.** A near-black canvas (`Theme.background`), raised
  surfaces (`Theme.surface`), white text. The app forces dark mode.
- **Cyan and magenta** are the brand. Cyan (`Theme.cyan`, also the asset
  catalog accent) is the primary — actions, selections, "correct".
  Magenta (`Theme.magenta`) is the counterpoint — urgency, "lower",
  eliminations, tie-breakers. Nothing else gets to be loud: everything
  non-accent is `Theme.quietFill` fills and `Theme.hairline` outlines.
- Buttons are neon capsules with a soft glow (`PrimaryButtonStyle`, tint
  cyan by default, magenta where it means the opposite thing); secondary
  actions use `QuietButtonStyle`.
- Rounded SF type everywhere (`Theme.display/title/headline/…`), uppercase
  kerned kickers for phase labels ("ROUND 2").
- Continuous-corner cards (`.card()`, 20pt), capsule chips for players,
  neon-leaning 8-color player palette in `PlayerStyle` led by the brand
  cyan and magenta.
- Playing cards are bright white with ink/magenta pips — the one bright
  object on the table.
- Phases cross-fade with a slight scale (see `GameScreen.contentKey`) —
  motion is soft and brief, never bouncy.

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
