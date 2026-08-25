# Contributing to Tappi

Thanks for your interest. Tappi is a small, focused project — this guide should be enough
to get productive in a few minutes.

## Development setup

**No Xcode required**, the Command Line Tools are enough:

```bash
xcode-select --install
```

Requirements: macOS 14 or later, Swift 5.9+.

```bash
git clone https://github.com/leonatwork/Tappi.git
cd Tappi
./setup-signing.sh     # once, see below — do this before your first build
./build.sh --install
```

### Why `setup-signing.sh` is not optional

macOS ties granted permissions to the code signature. Ad-hoc signed apps are identified by
the hash of their binary, which means **every rebuild invalidates the granted Accessibility
and Screen Recording permissions** — the checkbox stays visible in System Settings but no
longer applies, and Tappi reports missing Accessibility while everything looks correct.

```
ad-hoc        designated => cdhash H"..."               ← changes on every build
certificate   designated => certificate leaf = H"..."   ← stable
```

`setup-signing.sh` creates a local, self-signed identity in your login keychain for this.
No admin password is needed. Skip it and you will be re-granting permissions after every
single build — which costs more time than reading this section.

## The one design principle

**Nothing is computed on the hotkey path.**

Tappi exists because comparable tools compute their window previews *while the user waits*.
Anything between keypress and visible panel is therefore off limits for work that could
equally happen before or after:

- The window list is maintained continuously in the background (`WindowStore`), driven by
  Accessibility notifications — not by the keypress.
- Accessibility calls **never** run on the main thread and always carry a timeout. A wedged
  third-party app must not be able to block the switcher.
- The panel is created once at launch and merely ordered in and out afterwards.
- Previews are purely additive: the panel appears immediately with app icons, previews fade
  in asynchronously. Nothing ever waits for them.

As a benchmark: 1–2 ms from keypress to visible panel with a dozen windows. If you touch
that path, measure before and after:

```bash
TAPPI_DEBUG=1 /Applications/Tappi.app/Contents/MacOS/Tappi
```

That logs every key event with its swallow decision, plus the latency of each session
(`visible after … ms`). A real find from development: a single
`CGPreflightScreenCaptureAccess()` call per window cost 120–160 ms.

## Where things live

| File | Role |
|---|---|
| `WindowStore.swift` | Always-current window list and MRU order |
| `SwitcherController.swift` | State machine of one session (the Windows rules) |
| `EventTap.swift` | Intercepting key events before the focused app sees them |
| `SwitcherPanel.swift` | The pre-built overlay window |
| `SwitcherView.swift` | Tile layout and drawing |
| `ThumbnailProvider.swift` | Asynchronous previews via ScreenCaptureKit |
| `SystemSwitcher.swift` | Taking over ⌘Tab, with a guaranteed hand-back |
| `AX.swift` | Accessibility calls with timeout protection |
| `Diagnostics.swift` | Startup log for a program with no console |
| `StatusItem.swift` | Menu bar menu |

## Pitfalls that have already cost time

- **Keyboard layouts.** The key above Tab reports different keycodes: ANSI gives 50, ISO
  (German) gives 10 there and puts 50 on `<`. When testing shortcuts, check the keycode the
  *physical key* sends — a synthetic event carrying the keycode your own code expects tests
  nothing at all.
- **Flipped views.** `SwitcherView` deliberately works in AppKit's bottom-left coordinates.
  Setting `isFlipped = true` makes the grid maths more readable but mirrors every image
  drawn into it vertically.
- **⌘Tab is not an ordinary shortcut.** The window server handles it as a *symbolic hot
  key* before any event tap sees it. Intercepting the key is not enough; the hot key has to
  be disabled. If you work on this, make sure it is **always** handed back — otherwise the
  machine is left with no window switcher at all.
- **Launched from a terminal**, Tappi inherits the terminal's permissions. For an honest
  permission test, launch the app normally and read the diagnostics log.

## Pull requests

- One topic per PR.
- Describe **why** the change is needed, not just what it does. The same goes for code
  comments: the code says what happens, comments should explain why it is done this way and
  not another.
- Changes on the hotkey path should come with before/after measurements.
- The build must be warning-free: `swift build -c release`. CI enforces this.
- Please describe how you tested. Tappi has many states that can only be checked manually
  (multiple Spaces, minimized windows, multiple monitors, missing permissions).

## Reporting bugs

Please attach the diagnostics log (menu bar icon ▸ *Open diagnostics log*, or
`~/Library/Application Support/Tappi/diagnostics.log`) along with your macOS version and
whether you are on Apple Silicon or Intel. The log contains no window titles or other
content — only startup state and permissions.

## Language

Documentation is written in English. A German translation of the README lives in
[README.de.md](README.de.md); the English version is authoritative and updated first.
