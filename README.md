# SovEmu.iOS

The iPhone and iPad client for [SovEmu](https://github.com/sovereign-media/SovEmu): sign in to a
SovEmu server, pick a system and a game, and play it streamed over WebRTC with a game controller
or the touch controller.

Checked out as a submodule of `SovEmu` (unpinned, `branch = main`); it builds on its own.

## Layout

| Path | What |
|---|---|
| `project.yml` | The Xcode project's source of truth (XcodeGen). `SovEmu.xcodeproj` is generated and gitignored. |
| `Packages/SovEmuKit` | Swift 6 package: the input wire protocol and the API client and models. Its tests use the same byte vectors as `SovEmu.Protocol`, `SovEmu.Web` and `SovEmu.Android`. |
| `Apps/Mobile` | The SwiftUI app: sign-in, system carousel, game list, player (WebRTC via `stasel/WebRTC`, GameController input, touch controller). |

## Building

You need Xcode 26+ and XcodeGen (`brew install xcodegen`).

```bash
(cd Packages/SovEmuKit && swift test)
scripts/fetch-webrtc.sh      # the pinned WebRTC xcframework, into Packages/WebRTC (gitignored)
xcodegen generate
open SovEmu.xcodeproj    # or: xcodebuild -scheme SovEmu -destination 'generic/platform=iOS Simulator' build
```

## Using it

1. First-run setup (the admin account) happens in a browser at the server's address.
2. In the app, enter the server address (for example `http://192.168.1.20:8080`) and sign in.
   iOS asks for local-network access the first time.
3. The server must advertise an address the device can reach (`SOVEMU_ADVERTISE_IP`, the host's
   LAN address), with UDP 50000-50009 open.

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
- **Touch controller:** shown when no controller is connected.

## Licence

Free software under the [GNU Affero General Public License v3.0 or later](LICENSE)
(`AGPL-3.0-or-later`), as the SovEmu server is. You may use, change and share it; if you give
others a modified version, or run one they use over a network, you must offer them its source.
Its dependencies keep their own licences.
