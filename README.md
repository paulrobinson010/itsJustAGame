# It's Just a Game

An iOS party game for friends and family. One person starts a game, sends
everyone a personal invite link, and the group plays a series of mini games.
A spinning wheel picks who chooses each round's game — the first mini game is
**Sense of Direction**.

Everything the game sends between devices is **end-to-end encrypted**.

## How it works

### Game flow

1. **Create** — the host picks how many rounds it takes to win, how many
   players, and their names (every player must be named). Names can be
   typed or **picked from contacts** — a searchable picker with your
   frequent players pinned on top (iOS exposes no API for the Phone app's
   Favourites, so "frequent" means people you've picked before in this
   app). Contacts are read on-device only: the name goes into the
   encrypted config, the phone number stays on the host's phone. The app
   generates a personal invite link for every player except the host.
   Players picked from contacts get a one-tap **iMessage invite** from the
   lobby — the composer opens pre-addressed with their link (iOS requires
   the sender to tap Send). Everyone else uses the share sheet.
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
6. **Rematch without links** — when a game ends, the host taps "Rematch":
   a fresh game (new ID, fresh key) is announced over the old game's
   encrypted stream, every other player **joins automatically**, and the
   new game **starts on its own** once everyone is in (or after ~25s with
   whoever came). No links, no lobby taps. Keys still rotate every game;
   colors are re-dealt. Finished games store their result: reopening one
   shows the winner and standings instantly (no replay) with "Play again —
   same crew" for the host. The create screen also remembers your last
   rounds-to-win, can refill "same players as last game", and the contact
   picker multi-selects — while the lobby's "Invite all by iMessage" walks
   the pre-addressed composers back-to-back.
7. **Ties share** — when several players win a point or a round together,
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

### Lightning

A reaction duel. The screen goes dark — "wait for it…" — then flashes cyan
at a random moment rolled by the host. Tap the instant it flashes; your
reaction time is measured **locally in milliseconds against the shared
flash timestamp**, so network latency never affects fairness. Tap before
the flash and it's a false start (you can't win that flash); never tap and
you score nothing. Fastest finger takes the point, exact ties share, first
to 3 points wins the round. Caveat: the flash moment relies on device
clocks being NTP-synced (normally within tens of ms) — a badly skewed
clock would make the flash feel early/late on that device.

### Put Your Finger On It

Geography by feel. A bare satellite map appears — no place names, no
borders — and everyone is asked where a place is ("Where is Algeria?").
Tap to drop your pin (adjust freely), lock it in before the 15 seconds
run out. Closest pin to the place's capital takes the point; first to 3
points wins the round. One region per round, drawn from a curated atlas
(`FingerAtlas`): Europe, Africa, Asia and South America ask countries;
the United States region asks states (target: the state capital).
Alaska and Hawaii are omitted from the US region since they sit outside
the continental map view. The capital's location stays on the host until
the reveal, which shows the starred capital, everyone's pins, and
distances in km.

### Ten Seconds

The clock counts up on screen, then hides at 3 seconds. Keep counting in
your head and tap when you think it hits the target — which the host
varies between 7 and 15 seconds each turn. Time is measured locally
against the shared start timestamp (latency-immune, like Lightning), your
own tap stays hidden until the reveal, and closest to the target takes
the point; first to 3 points wins the round, exact ties share.

### Push Your Luck

Greedy-pig dice. Each run opens with one free (never-skull) die in the
pot; before every subsequent die, everyone still riding secretly chooses
**push** (ride on, cyan) or **bank** (copy the current pot into your
total and sit out the run, magenta). A skull busts everyone still riding
to nothing for that run. Silence defaults to banking, so a dropped
connection can't bust you. The round finishes its current run, then
everyone with 20+ banked wins it (shared if several cross together);
after 12 runs the leaders take it.

### Gold Rush

Schelling-point greed. Every turn the host deals a fresh 5×5 board of coin
values (one 10, one 8, and a long tail — same spread, shuffled positions)
that everyone sees identically. Each player secretly stakes **one**
square within 12 seconds: alone on it, you pocket its coins; two or more
on the same square and nobody scores it. A tapped-but-unconfirmed square
auto-stakes at the deadline; no pick sits the turn out. First to 30 coins
wins the round (shared if several cross together); leaders after 15 turns.

### Eyeball It

Perception. A cloud of 40–150 dots flashes for two seconds — identical on
every device, regenerated from a seed in the encrypted turn message —
then vanishes. Dial in your guess within 12 seconds (slider plus
nudge buttons). Closest to the true count takes the point; first to 3
points wins the round.

### Perfect Circle

Draw the roundest circle you can: one finger, one stroke, ten seconds.
Lifting your finger locks it in (tiny accidental strokes clear and let
you retry). Players submit their raw stroke and the **host scores it**
(radius wobble, full-loop coverage, end-gap closure — see `CircleScore`),
so scores are never client-claimed. The reveal shows everyone's actual
drawings side by side. Highest score takes the point; first to 3 wins
the round.

### Sort Circuit

Nine numbered tiles scattered identically on every device (seeded
layout). Tap 1→9 as fast as you can — a wrong tap flashes and adds a
one-second penalty. Timing runs locally against the shared start
timestamp, so latency never matters. Fastest penalty-inclusive time
takes the point; first to 3 wins the round.

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
- Two type voices: **Chakra Petch** (bundled, SIL OFL — see
  `ItsJustAGame/Fonts/OFL.txt`) for display sizes, titles, headlines,
  buttons and the uppercase kerned kickers ("ROUND 2"); rounded SF for
  body and small text. The wordmark is Chakra Petch in the
  cyan→magenta `Theme.brandGradient` with a soft glow — reserve the
  gradient for wordmarks and hero moments.
- Continuous-corner cards (`.card()`, 20pt), capsule chips for players,
  neon-leaning 8-color player palette in `PlayerStyle` led by the brand
  cyan and magenta. Each player is **dealt a color at random by the host
  when the game is created** (stored in the encrypted game config) and
  keeps it everywhere for the whole game — chips, wheel segments, map
  pins, lines, grid reveals, your own hiding spot and pin. Look up colors
  via `session.color(slot)` or `player.color`, never by slot arithmetic.
- Playing cards are bright white with ink/magenta pips — the one bright
  object on the table.
- Phases cross-fade with a slight scale (see `GameScreen.contentKey`) —
  motion is soft and brief, never bouncy.
- **Sound** (`Audio/SoundPlayer.swift`; no in-app toggle — the silent
  switch and volume buttons are the controls): tiny synthesized arcade
  WAVs in `ItsJustAGame/Sounds/`. The wheel clicks per
  segment crossing so clicks slow with the wheel; the tie-breaker rolls a
  drum under its spin; wins get fanfares, eliminations a downward blip,
  Lightning a zap at the flash. One switch in `GameScreen.playSound(for:)`
  maps phases to sounds — new games add a case there. Ambient session:
  the silent switch mutes it and it mixes with the user's music.
- **iPad**: native (all orientations), with game content capped at a 700pt
  column; iPhone stays portrait.

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

## Universal links (going live)

Everything for tappable `https://itsjustagame.robbo-online.uk/join/…`
links is already in the repo — the `docs/` folder is a ready GitHub Pages
site (AASA file, landing page, join page) and the app carries the
Associated Domains entitlement and parses both link forms. To switch on:

1. DNS: `CNAME itsjustagame.robbo-online.uk → paulrobinson010.github.io`.
2. GitHub → Settings → Pages: deploy from branch, folder `/docs`; set the
   custom domain (the `docs/CNAME` file already matches); enforce HTTPS.
3. Edit `docs/.well-known/apple-app-site-association`: replace `TEAMID`
   with your 10-character Apple Team ID (and the bundle ID if you changed
   it from `com.paulrobinson.ItsJustAGame`).
4. Verify: `curl https://itsjustagame.robbo-online.uk/.well-known/apple-app-site-association`
   returns the JSON.
5. Flip `InviteLink.useUniversalLinks` to `true`, rebuild, delete and
   reinstall the app on each device (iOS fetches the AASA at install).
6. If tapped links stubbornly open Safari instead of the app, the usual
   culprit is the AASA content-type GitHub Pages serves; fronting the
   subdomain with free Cloudflare and forcing `application/json` on that
   path fixes it.

The privacy model is unchanged: the key rides in the URL fragment, which
browsers never send to a server — GitHub only ever sees the random game
ID and slot. The join page's copy button reads the fragment locally.

## Roadmap

- More mini games (the wheel/choice mechanic already supports them —
  add a case to `MiniGameType` and a view per phase).
- CloudKit push subscriptions instead of polling.
- Host resume mid-game (the message stream already makes this possible).
- Universal links (`https://…`) alongside the custom scheme — the key
  already rides in the URL fragment, which never reaches the server.
