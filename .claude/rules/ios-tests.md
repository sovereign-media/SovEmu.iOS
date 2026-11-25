---
paths:
  - "Packages/**/Tests/**"
---

# SovEmu.iOS: tests

- **Swift Testing only** (`import Testing`, `@Test`, `#expect`, `#require`), never XCTest. Suites
  are plain `struct`s; `@Suite` only when a suite needs traits.
- **Logic is tested in SovEmuKit** on the host (`swift test` in `Packages/SovEmuKit`, seconds).
  The app target has no tests: what needs one moves into the package.
- **A port keeps its cases.** A SovEmuKit type ported from SovEmu.Android or SovEmu.Web gets the
  same cases as its counterpart's suite; the protocol and controller suites use the shared
  vectors. Add a case to every client together.
- **No real network or clock**: HTTP is stubbed with a `URLProtocol` (`AuthTests`), and time comes
  through the injected `now` closure, never a real sleep. A suite that waits on concurrent work
  waits for the state it checks, not a fixed number of yields, or it fails at random under
  `--parallel`.
- **Each test says why it matters** in its name or a comment: the failure it prevents, not a
  restatement of the code.
- `swift` and `xcodebuild` need Xcode's toolchain, not the Command Line Tools: when
  `xcode-select -p` names `/Library/Developer/CommandLineTools`, every macro fails with `plugin
  for module '…Macros' not found`, which looks like a code error and is not one. Run `sudo
  xcode-select -s /Applications/Xcode.app` once, or prefix the command with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
