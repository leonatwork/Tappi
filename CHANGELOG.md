# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-08-25

First release.

### Added

- Window switching modelled on Windows Alt-Tab: between **windows** rather than apps, in
  MRU order, with index 1 preselected — so a quick press switches to the last used window.
- Re-ordering only on release, which is what makes toggling back and forth between two
  windows work.
- <kbd>⌘</kbd><kbd>Tab</kbd> by default; the system switcher is taken over while Tappi is
  able to do the job, and handed straight back otherwise.
- <kbd>⌘</kbd><kbd>`</kbd> for windows of the current app (ISO and ANSI layouts).
- <kbd>⇧</kbd> to cycle backward, arrow keys, <kbd>Esc</kbd> to cancel, <kbd>⌃</kbd> for a
  sticky list, mouse control including "✕" to close a window.
- Live previews via ScreenCaptureKit, loaded asynchronously — the panel never waits.
- Menu bar settings: modifier, show delay, tile size, previews, minimized windows, other
  Spaces, hidden apps, mouse selection, launch at login.
- Diagnostics log and single-instance guard.

### Performance

1.0–1.7 ms from keypress to visible panel with 12 windows and previews enabled; about
0.6 % CPU time when idle.
