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
6. **Rematch without links** — only the host can start one. When a game
   ends the host taps "Rematch": a fresh game (new ID, fresh key) is
   announced over the old game's encrypted stream, and every other player
   gets a **join request** — on the game-over screen, on a reopened
   finished game, or as a "Rematch waiting" card on the home screen (the
   invite is also parked at a well-known record, `g<oldID>-rematch`,
   sealed with the old game's key, and the home screen checks recent
   games on every launch and foreground). Tapping the request joins them;
   the new game **starts on its own** once everyone is in (or after ~25s
   with whoever came). No links; keys still rotate every game and colors
   are re-dealt. Finished games store their result: reopening one
   shows the winner and standings instantly (no replay) with "Play again —
   same crew" for the host. The create screen also remembers your last
   rounds-to-win, can refill "same players as last game", and the contact
   picker multi-selects — while the lobby's "Invite all by iMessage" walks
   the pre-addressed composers back-to-back.
7. **Practice mode** — "Practice on your own" on the home screen plays
   any single game round after round, solo. It's the full stack — a
   one-player hosted game whose engine and session talk over an
   in-memory `LoopbackTransport` — so nothing touches CloudKit and
   nothing is saved. The wheel is skipped; leaving is the only way out.
8. **Ties share** — when several players win a point or a round together,
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

Your own hiding spot is **never left marked on screen** — a co-located
opponent could otherwise just glance at your phone. After you hide, a
**hold-to-reveal** button ("Hold to check your spot") shows it only while
pressed and hides it again on release; a seeker who taps their own square
gets a faint dot as a reminder. The spot itself is only ever stored
locally (`myHideCells`); the host has the authoritative copy.

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
- **Version handshake** (`AppProtocol.current`): the host stamps its wire
  version into `GameConfig`, and each joiner reports its own in the `join`
  message. The host (authoritative) keeps any game an older player can't
  decode out of the wheel menu, so a mixed-version table only ever plays
  games everyone can read. A joiner whose host is on a *newer* version than
  it understands is told to update. All the version fields are optional, so
  new and old builds still decode each other's messages — only the game set
  is gated. Bump `AppProtocol.current` whenever the wire format changes and
  tag any new/changed game with its `minProtocolVersion`.

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

### Colour Clash

The Stroop test as a race. A colour name flashes up printed in a
different colour — "GREEN" in red ink — and you tap the colour it's
**printed in**, not the word, through a run of eight prompts. The
sequence is regenerated identically on every device from a seed (like
Sort Circuit's tile layout); each device validates taps locally and
reports only its penalty-inclusive time, so the host scores it
latency-free. Wrong taps flash and add a second. Fastest run takes the
point; first to 3 wins the round. The fun is watching clever adults
overthink it while the kids just see the colour. (Inherently a colour-
vision game — buttons are name-labelled, but the prompt's hue is the
whole point.)

### Globetrotter

Put Your Finger On It's globe-scale sibling, sharing the same map
machinery (frozen satellite view, closest-pin scoring, dashed-distance
reveal). Instead of a region's capital, it names a **famous landmark**
("Where is the Taj Mahal?") over a bare view of the whole planet —
continents by shape, no labels — and you drop your pin anywhere on Earth
within 15 seconds. Closest takes the point; first to 3 wins the round.
The bank is `LandmarkAtlas`: ~175 globally-recognisable landmarks and
natural wonders (`name · country · continent · coordinate`), spread
across all six continents so it isn't Euro/US-heavy. Coordinates are
city-level approximate — invisible at world scale, and every player is
scored against the same target. The landmark's location stays on the
host until the reveal (starred, with everyone's pins and distances).

### Ten Seconds

The clock counts up on screen, then hides at 3 seconds. Keep counting in
your head and tap when you think it hits the target — which the host
varies between 7 and 15 seconds each turn. Time is measured locally
against the shared start timestamp (latency-immune, like Lightning), your
own tap stays hidden until the reveal, and closest to the target takes
the point; first to 3 points wins the round, exact ties share.

### Push Your Luck

Greedy-pig on a wheel. The pot wheel has seven segments — the values
1–5 plus two 💀 busts (`DiceWheel.segments`, busts spread apart), so the
bust odds are a real 2-in-7. Each run opens with one free (never-bust)
value in the pot; before every spin, everyone still riding secretly
chooses **ride** (cyan) or **bank** (copy the current pot into your
total and sit out the run, magenta). The reveal then spins the wheel —
same host-decides / every-device-animates mechanic as the game-select
wheel, slowing clicks and all — and a 💀 busts everyone still riding to
nothing for that run. Anyone the pot would carry to the target is
**auto-banked** (riding past a guaranteed win is pointless). Silence
defaults to banking, so a dropped connection can't bust you. The round
finishes its current run, then everyone with 20+ banked wins it (shared
if several cross together); after 12 runs the leaders take it.

### Gold Rush

Schelling-point greed. Every turn the host deals a fresh 5×5 board of coin
values (one 10, one 8, and a long tail — same spread, shuffled positions)
that everyone sees identically. Each player secretly stakes **one**
square within 12 seconds: alone on it, you pocket its coins; two or more
on the same square and nobody scores it. A tapped-but-unconfirmed square
auto-stakes at the deadline; no pick sits the turn out. First to 30 coins
wins the round (shared if several cross together); leaders after 15 turns.

### Eyeball It

Perception. A cloud of 15–250 dots flashes for two seconds — identical on
every device, regenerated from a seed in the encrypted turn message —
then vanishes. Consecutive clouds always differ by at least 40 dots, so
turns never feel samey. The visible window counts from the moment each device
actually renders the dots (not the shared start), so polling latency
never shortens your look; a device arriving long after the window skips
straight to guessing. Dial in your guess within 12 seconds (slider plus
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

### Size It Up

A shape (square, circle, triangle or diamond) flashes on a square canvas
at a random size, then vanishes — you get two seconds to burn it in. Then
draw it back at the same size from memory, one stroke, ten seconds. The
device measures your drawing's size (the larger side of its bounding box,
as a fraction of the canvas) and submits just that number; the **host
scores** it against the target, closest wins. Everything is measured
locally, so latency never matters. First to 3 wins the round. Simplify
leaves a faint trace of the target up while you draw — barely-there
(level 1), clearer (level 2), or a near-solid outline to trace (level 3).

### Sort Circuit

Nine numbered tiles scattered identically on every device (seeded
layout). Tap 1→9 as fast as you can — a wrong tap flashes and adds a
one-second penalty. Timing runs locally against the shared start
timestamp, so latency never matters. Fastest penalty-inclusive time
takes the point; first to 3 wins the round.

### Marble Maze

Tilt to roll a ball through a maze to the exit — fastest escape wins the
point, first to 3 wins the round. Each turn the host sends a seed and
every device regenerates the **identical** maze (a perfect maze from a
recursive-backtracker on a 6×6 grid — `MazeModel`), so it's a fair race
and never the same maze twice. The ball is simple continuous physics:
tilt (roll/pitch) accelerates it, damping keeps it controllable, and it's
pushed out of wall segments by circle-vs-segment collision. Time is
measured locally from the shared start, latency-immune. Needs a real
device (no motion in the Simulator). Simplify: gentler, slower ball
(level 1); the solution path drawn faintly (level 2); the path drawn
boldly, plus the gentler ball (level 3).

### Spirit Level

Tilt the phone (left–right roll, read from CoreMotion device attitude) to
keep the bubble between two markers — but the markers **drift, faster and
faster**. The zone's path is two summed sinusoids on an accelerating time
base, regenerated identically on every device from the turn's seed. The
clock runs as long as you stay inside; the moment you slip out (past a
short grace) your time locks in, capped at 20 seconds. A brief dip back
inside is forgiven so hand jitter doesn't end the run. Longest hold takes
the point; first to 3 wins the round. Timed locally, so latency never
matters. Needs a real device (the Simulator has no motion). Simplify
widens the gap between the markers, so the zone is easier to stay inside
(×1.8 / ×2.6 / ×3.6).

### Pour It

Tip the phone to either side (roll) to pour, level off to stop, and hit a
target fill line without spilling. The glass on screen tips the way you
roll — clockwise or anti-clockwise — and either direction pours. Fill is
integrated locally from the roll magnitude each frame (pour rate ∝ how far
past ~6° you tip), so it's latency-free; overflowing past the top spills,
and a clean pour always beats a spill. Closest to the line takes the
point; first to 3 wins the round. Needs a real device. Simplify: slower
pour and a green band round the line (level 1), plus a live fill %
(level 2), and at the top level it simply won't overflow past the line
(level 3).

### Loudest

On GO, everyone shouts; the loudest wins the point, first to 3 wins the
round. A shared `MicService` (AVAudioEngine tap) reduces the mic to a 0–1
loudness on the render thread — **raw audio is never recorded, stored, or
transmitted**, only a number 0–1000. The score is a *sustained* loudness
(a slow-attack smoothed peak) put through a curve, so a one-off spike
won't do it — you have to hold a genuinely loud shout for the best part of
a second to near 1000. Measured on each device, so it's latency-free.
Needs mic permission (and a real device). Simplify quietly scales your
loudness up (×1.15 / ×1.3 / ×1.6) — invisible at the reveal.

### Blow It Out

Blow at the phone to snuff two rows of birthday candles (20 of them); the
device integrates sustained loudness (above a threshold, so a shout won't
do it) into a candle count, most out wins — you can't clear the lot in the
window, so it's a race for the most. First to 3 rounds. Same mic-to-number
privacy as Loudest. Simplify makes the candles easier to blow out
(×1.3 / ×1.6 / ×2).

### Hum It

The reference note plays (a sine tone built in memory — `ToneWAV`), then
you hum it back. The device estimates your hum's pitch by autocorrelation,
takes the median over the window, and reports the error in **cents**;
closest wins. Only the cents error leaves the phone. Needs mic + a real
device. Simplify: level 1 plays the note longer and shows a higher/lower
arrow; levels 2–3 show a live cents readout.

### Crack the Safe

Twist the phone like a safe dial to spin each digit of the (shown) combo
into place. The device integrates the twist rate (`MotionService`, gyro
about the screen-normal) into a 0–9 dial and locks a digit once you settle
on it; fastest to enter all three wins. Only the elapsed time leaves the
phone, measured locally against the shared start — latency-free. Needs a
real device. Simplify: level 1 is more forgiving about "settled"; level 2
turns the dial green on the right digit; level 3 locks the instant you
pass it.

### Feel the Beat

A short rhythm thumps through the phone — a full-strength haptic and a
punchy low drum beat (a synthesized tone, played loud), no beat shown —
then you tap it straight back. The device compares your tap gaps to the
pattern and reports the average error in ms; closest wins. Only the error
leaves the phone. Works on iPad too (the drum hits carry it where there's
no haptics). Simplify: level 1 plays the pattern twice; level 2 adds a
visual pulse on each beat; level 3 keeps a visual metronome looping so you
can tap along.

### Steady Hand

Endurance. A glowing ring drifts around the board and slowly shrinks —
the drift is two summed sinusoids per axis, regenerated identically on
every device from a seed, gently accelerating so the endgame bites. Keep
your finger inside it; the moment you slip out (or lift), your time locks
in, measured locally against the shared start. Making it to 40 seconds is
a full ride. Longest hold takes the point; first to 3 wins the round.

### Showdown

Rock, paper, scissors — against the whole table at once. Everyone throws
in secret within 8 seconds (silence gets a random throw, and never
throwing at all loses to everyone who threw). You score a win for every
player you beat, so a lone paper against two rocks sweeps. First to 5
accumulated wins takes the round (shared if several cross together);
after 12 turns the leaders take it.

### Tap Frenzy

Five seconds. Tap as many times as you can. That's it. Counts are
measured locally against the shared start, most taps takes the point
(exact ties share), first to 3 points wins the round. Scientifically
proven to be the loudest thirty seconds of any family gathering.

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

## Simplify (per-player help)

The host can switch **Simplify** on for any player when creating the game
and pick a level: *A little help*, *A big help* or *Basically cheating*
(`AssistLevel`, stored on `PlayerInfo` inside the encrypted config, carried
into rematches, restored by "Same players as last game"). It's invisible in
play — nothing on other screens shows who has it.

Every game implements all three levels:

| Game | A little help | A big help | Basically cheating |
| --- | --- | --- | --- |
| Sense of Direction | wide glowing arc on the dial containing the true bearing | narrower arc | very tight arc |
| Hide & Seek | 5 empty squares ruled out (dimmed + locked) on your seek turn | 10 ruled out | everything ruled out except the hiders plus two decoys |
| Higher or Lower | rank odds shown | better call recommended | the host pre-draws and marks the actually-correct button |
| Repeat After Me | next pad blinks a ring when you stall | ring always on next pad | next pad fully lit |
| Lightning | dot turns cyan just before the flash | visible 3-2-1 countdown | countdown + your time counts ×0.6 |
| Put Your Finger On It | big hint circle on the map (off-centre from the capital) | smaller circle | tiny circle |
| Globetrotter | continent named + big hint circle (off-centre) | smaller circle | tiny circle |
| Ten Seconds | clock visible ~1.7× longer | ~2.5× longer + silent pulsing beat | clock never hides |
| Push Your Luck | bust odds shown | plain-English bank/ride advice | host pre-spins — you're told if the next spin busts |
| Gold Rush | top-3 squares outlined | + others' picks appear live on your board | + taken squares lock, so you can't clash |
| Eyeball It | dots linger ~1.6× longer | + slider narrows around the count (jittered) | + "it's between X and Y" |
| Perfect Circle | faint dashed guide ring to trace | bold guide ring | + the host adds 7 to your score |
| Size It Up | faint target trace left up while drawing | clearer trace | near-solid outline to trace |
| Sort Circuit | next number glows when you stall | next number always glows | + slips cost no time |
| Colour Clash | correct button glows when you stall | correct button always glows | + slips cost no time |
| Marble Maze | gentler, slower ball | + solution path drawn faintly | bold solution path + gentle ball |
| Loudest | your loudness ×1.15 | ×1.3 | ×1.6 |
| Blow It Out | candles ×1.3 easier | ×1.6 | ×2 |
| Hum It | note plays longer + higher/lower arrow | live cents readout | live cents readout |
| Crack the Safe | more forgiving "settled" | + dial goes green on the right digit | + locks the instant you pass it |
| Feel the Beat | pattern plays twice | + a visual pulse on each beat | + a visual metronome to tap along to |
| Spirit Level | wider gap between the markers (×1.8) | ×2.6 | ×3.6 |
| Pour It | slower pour + green band round the line | + live fill % | + can't overflow past the line |
| Steady Hand | ring drawn (and judged) 1.35× bigger | 1.7× bigger | 2.1× bigger |
| Showdown | what-beats-what reminder | others' throws appear live | + told which throw beats the most right now |
| Tap Frenzy | your window quietly runs 1.5s longer | 3s longer | 5s longer |

Mechanics that need host secrets (safe squares, the pre-drawn card, hint
circles, the pre-rolled die, live Gold Rush picks, live Showdown throws)
ride along in the turn messages keyed by slot (`assistSafe`,
`assistCorrect`, `assistHints`, `assistPeek`, `assistTaken`,
`assistThrown`) — every device receives them but only the assisted device
renders its own. For Gold Rush and Showdown the host re-publishes the
turn message as picks land, which is safe because `contentKey` keeps the
view's identity stable within a turn. Scoring itself never bends in ways
the reveal would expose: the only tweaks are Lightning's ×0.6 (applied on
the assisted device) and the Perfect Circle bump (host-side) — both
invisible in the results. Audible cues never change with assist — the
room would hear it.

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

### App Store screenshots

In the **simulator only**, the home screen shows a **Screenshot tour**
button. It steps through every screen — lobby, wheel, all twenty-six games
mid-play, reveals, round end, tie-break, game end — with demo players
(Mum, Dad, Freddy and Lilly) and believable made-up scores, holding each
screen for about two seconds so you can grab shots with **⌘S**. Tap to
pause/resume, swipe left/right for next/previous, long-press to exit. It
runs entirely offline (no CloudKit), and the button is compiled out of
device builds entirely. Works on iPhone and iPad simulators alike.

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
