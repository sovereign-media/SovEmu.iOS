# SovEmu.iOS

The iPhone and iPad client for [SovEmu](https://github.com/sovereign-media/SovEmu): sign in to a
SovEmu server, pick a system and a game, and play it streamed over WebRTC with a game controller
or the touch controller.

Checked out as a submodule of `SovEmu` (unpinned, `branch = main`); it builds on its own.

## Layout

| Path | What |
|---|---|
| `project.yml` | The Xcode project's source of truth (XcodeGen). `SovEmu.xcodeproj` is generated and gitignored. |
| `Packages/SovEmuKit` | Swift 6 package: the input wire protocol, the API client (Apollo iOS, its operations in `Sources/SovEmuKit/GraphQL/operations.graphql`, generated into `Generated/` from a copy of SovEmu's `schema.graphql`) and models, and the logic the screens draw (the game list's search, filters, sorts and A–Z jump; the start's progress bar; the button-to-frame measurement and the stats rows; several accounts and servers, *Who's watching?*, *Choose a server* and proxy headers), ported from SovEmu.Android's `core` with the same test cases. Its protocol tests use the same byte vectors as `SovEmu.Protocol`, `SovEmu.Web` and `SovEmu.Android`. |
| `Apps/Shared` | What both apps draw alike: the player, the stream, controllers, the in-game menu's logic and the screens a TV and a phone share. |
| `Apps/TV` | The Apple TV app (`SovEmuTV`), after SovEmu.Android's TV app: the dock, Home, a system's page and game panel, search, sign-in with several accounts and servers, and the in-game menu. |
| `Apps/Mobile` | The iPhone and iPad app (`SovEmu`), after the Android app's screens: sign-in; Home, Search, Systems and the account as tabs (a sidebar on an iPad); a system's cover grid and game panel; the player (WebRTC: LiveKit's libwebrtc build, GameController input, touch controller); the screensaver and menu music. |

## Building

You need Xcode 26+ and XcodeGen (`brew install xcodegen`).

```bash
scripts/codegen.sh           # after changing a .graphql document (scripts/sync-schema.sh: a new server schema)
(cd Packages/SovEmuKit && swift test)
scripts/fetch-webrtc.sh      # the pinned WebRTC xcframework, into Packages/WebRTC (gitignored)
xcodegen generate
open SovEmu.xcodeproj    # or: xcodebuild -scheme SovEmu -destination 'generic/platform=iOS Simulator' build
```

## Using it

1. First-run setup (the admin account) happens in a browser at the server's address.
2. In the app, enter the server address (for example `http://192.168.1.20:8080`) and sign in:
   *Sign in* opens the server's own sign-in page in the browser; *Sign in with a code* shows one
   (and a QR code) to approve at the server's `/device` page; or use a password, where the server
   allows one. The account's *Sign in a TV* approves a TV's code from the phone.
   iOS asks for local-network access the first time.
3. The server must advertise an address the device can reach (`SOVEMU_ADVERTISE_IP`, the host's
   LAN address), with UDP 50000-50009 open.

**Browsing:**
- **Home:** a hero of featured games (moving on every 9 s; swipe to change), then rows: Continue
  playing (where you left off, from the auto save's picture), Favourites, Systems, Recently
  added, Top rated, and one per collection. A card opens the game's panel on its system's page; the hero's
  Play starts at once (asking Continue or Start over when there is an auto save).
- **A system's page:** the covers in a grid, sorted by title (natural order: Mega Man 2 before
  10), recently played, release year or most played (remembered); Filters searches titles, makers
  and genres and keeps favourites, played or not, two players or more, and genres; Jump goes to a
  letter. A game's panel (beside the grid on an iPad, a sheet on an iPhone) shows its artwork and
  video snap, its ESRB rating icon (from the server's decoration set, which an admin may replace), facts (rating out
  of 5, ways to play, series, themes) and description, Continue / Start over or Play, starting from any save by its
  picture, the favourite, its collections, and its soft patch (one button steps through the
  original and each patch).
- **Search** looks across every system.
- **The account tab:** music in the menus (on; it follows the silent switch), the screensaver
  (games' video snaps after 3, 5 or 10 minutes without a touch or a button; off by default on an
  iPhone, five minutes on an iPad, and it keeps the screen awake in the menus while it is on), CRT
  scan lines over the menus (on), and signing out.

**Playing:**
- **Starting a game:** a loading bar follows the server's start (`startProgress`, four times a
  second) and never moves back; once the session is ready it says "Connecting", then "Checking
  your connection" while the worker measures the link, then "Starting the game" until the first
  picture arrives, and after 20 s that ☰ opens the menu. The bar sits in the middle over the save
  being continued, the game's picture or its box art, darkened; "Home network" or "Remote" in a
  chip top right, the game's system, title and core bottom left, and a spinner bottom right. Leaving at any point
  stops the session, even one still starting. The picture keeps the console's shape (4:3, or a
  handheld's own) and is framed by its system's decoration when the screen is wider than it.
- **In-game menu:** save to and load from four slots (and the auto save), each with its picture
  and age; change disc; turn cheats on and off, add them (Game Genie, Action Replay or raw codes)
  and delete them; controllers; stats; quit.
- **Stats** (in-game menu; remembered): the same rows as the other clients (estimated
  button→pixel, measured button→frame, input round trip, network RTT, jitter buffer, decode,
  resolution and fps, bitrate, packets lost, then how the server makes the stream, then the
  Network rows: home or remote, TURN server, transport, path, what was measured at the start,
  the rate it started at and the estimate now), and a graph
  of the last minute's latency. *Measured button→frame* times an input to the first frame shown
  after the worker's ack. The stats go to the server every second either way, from connecting
  (the round trip and the path, while it checks the connection), which lowers the bitrate for a
  device that falls behind.
- **Touch controls** appear when no controller or keyboard is connected, and go and come back as
  they connect and disconnect.

**Controls** (as `docs/CONTROLLERS.md` in SovEmu describes, shared with the web and Android clients):
- **Controllers** (Bluetooth or USB/Lightning) are recognised by model: Xbox, DualSense,
  DualShock 4 and Switch Pro by `productCategory`, anything else by name. Buttons map by
  position by default (bottom face = RetroPad B, right face = A).
- **Players:** each controller is its own player, in the order they connect (a new one takes
  the lowest free player, a disconnected one frees it). The keyboard and the touch controls are
  player 1.
- **Remapping:** in-game menu → Controllers. Change a device's player (for this session), or
  remap it for **this system** (its buttons by the console's own labels: a Mega Drive's A, B, C)
  or for **all systems** (the sixteen RetroPad buttons), with the console's pad and your
  controller drawn side by side and the chosen button lit on both. Pick a button and press the
  input to bind (tap B/○/A or Escape to cancel; hold it to bind that button itself). Mappings
  are saved to your account per controller model and system, so they follow you to the other
  clients; the page says whether yours or a default is in force, and "Reset to defaults"
  removes yours for that scope.
- **Keyboard:** arrows, Z (B), X (A), A (Y), S (X), Q (L), W (R), Enter (Start), Shift (Select);
  Tab fast-forwards, Backspace rewinds, Escape opens the menu.
- **In-game menu:** the ☰ button, Select+Start, Home or Escape. A controller drives it: the
  D-pad moves, the bottom face confirms, the right face goes back.
- **Fast-forward:** hold Select+R. **Rewind:** hold Select+L. (After mapping: the RetroPad
  buttons, wherever they are bound.)
- **Touch controller:** shown when no controller or keyboard is connected.

## Licence

Free software under the [GNU Affero General Public License v3.0 or later](LICENSE)
(`AGPL-3.0-or-later`), as the SovEmu server is. You may use, change and share it; if you give
others a modified version, or run one they use over a network, you must offer them its source.
Its dependencies keep their own licences.
