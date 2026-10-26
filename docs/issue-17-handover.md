# Issue #17 — handover

Issue: https://github.com/leonatwork/Tappi/issues/17

## Baseline and available evidence

The clean starting checkout was `afd0d74234702728962fb2415656e56b375d5782`,
identical to local `origin/master`. `origin/HEAD -> origin/master` and
`.github/workflows/build.yml` (`push.branches: [master]`) identify `master` as
the repository's default integration branch. There is no local `origin/main`.
The task's literal `origin/main` requirement therefore cannot be met; work uses
the supplied default-branch checkout without switching branches or incorporating
open PR changes. No commit, branch creation, push or PR creation was performed.

GitHub CLI access was denied by the environment's permission policy before
changes. The full online issue thread, comments, open PRs and remote repository
metadata could not be read. The structured issue description supplied in the
task is the available specification; unseen comments and PR dependencies remain
unverified. `CLAUDE.md` and `AGENTS.md` are absent from this checkout.
`CONTRIBUTING.md`, the current sources, existing XCTest style, package, build
workflow and localization checker were reviewed.

Issue #11 is already merged into this baseline as PR #22 (the starting commit).
The optional new field follows the existing decoder's per-field pattern. No
additional implementation of #11, dependency on an open PR, dependency package
or general CI change is needed for this patch.

## Binding decisions and qualifications

The structured description supersedes the older description preserved in the
issue's details block:

- Default screen is **active**, falling back to mouse, main, first, then no panel.
- Shrink tiles proportionally to **96 pt minimum width**, then truncate; no scrolling.
- `panelScreen` is optional, with `nil` meaning active. Existing JSON stays valid.
- Screen, layout settings and initial capacity are chosen once per session from
  cached geometry, without adding an AX query. Closing/quitting recomputes the
  layout for surviving entries using the same screen and settings.

The original expectation that *every* open window must remain visible conflicts
with the explicit minimum-size/truncation decision. The implementation follows
the structured AC-4: retain the **MRU prefix**, excluding the least recently used
tail from both drawing and keyboard actions. The phrase “überzählige (zuletzt
genutzte) Fenster abschneiden” is interpreted as truncating the ordered window
list, rather than discarding its most recently used head; preserving current and
previous windows also preserves quick-toggle behavior.

A screen too small for even one 96-pt tile plus existing padding cannot satisfy
both the minimum width and full containment. It produces an empty layout and no
session. If exactly one tile fits after truncation, that tile remains selectable.
The usual 92% width budget is preserved; exceptionally narrow screens may use the
remaining margin to fit a minimum-size tile inside `visibleFrame`.

## Acceptance criteria

All runtime assertions below await macOS execution; source review is not a test pass.

| Criterion | Implementation and regression coverage | Verification status |
|---|---|---|
| AC-1: active focused window on second screen | `PanelScreenSelection` converts cached AX/Quartz window bounds and selects the largest screen intersection; `SwitcherPanel.prepare` receives `WindowStore.entries.first?.frame`. Tests cover a left-hand screen and spanning windows. | Source reviewed; multi-monitor confirmation pending. |
| AC-2: mouse screen, including negative coordinates | Mouse coordinates remain in AppKit space. Tests cover negative x/y and a screen above primary. | Source reviewed; XCTest and manual check pending. |
| AC-3: main-screen setting preserves previous placement | `.main` ignores window/mouse, uses `NSScreen.main`, then first screen. Tests include a main index other than zero. | Source reviewed; manual confirmation pending. |
| AC-4: shrink, minimum width, truncate, contain and select | Pure layout receives count, tile width, column limit and `visibleFrame`. It preserves the original tile aspect ratio and column count, bounds rows and truncates tiles. Controller limits its own list before initial selection/delayed presentation, so Tab/arrows, commit, close and quit cannot target the truncated tail. Removal remaps selection to the same surviving window or its successor/last tile. Layout tests check containment and unique hit targets, overflow, minimum size, narrow/short screens and empty layouts; selection tests cover removal before/at the selected position. | Source reviewed; tests and mouse/keyboard checks pending. |
| AC-5: unchanged geometry when few windows fit | Original height formula, spacing, padding, width budget and column calculation are preserved. Tests assert exact three-window dimensions and normal multi-row wrapping. | Source reviewed; tests and visual comparison pending. |
| AC-6: previews use selected screen's 1x/2x factor | Panel retains chosen screen's scale and passes it explicitly to capture. `ThumbnailRequest` defines pixel dimensions and cache identity; tests expect 132×84 at 1x and 264×168 at 2x. Size/scale changes bypass a fresh incompatible cache entry; obsolete in-flight results cannot overwrite the current request. | Source reviewed; XCTest and ScreenCaptureKit confirmation pending. |
| AC-7: safe fallback without screens | Pure choice returns main index, first index, or nil. Panel preparation returns zero capacity with no screen; controller stays idle. No `screens[0]` fallback remains. Tests cover absent/invalid main and no screens in all modes. | Source reviewed; tests and unplug check pending. |
| AC-8: legacy JSON preserves settings, default active | Optional `panelScreen`; decoder integration and synthesized encoding. Tests decode a complete non-default legacy fixture, check nil/active default, explicit null and all three settings' round trips. | Source reviewed; XCTest pending. |
| AC-9: roughly 1–2 ms; clean ten-language checker | No new AX, permission, capture or disk call on presentation. Layout is closed-form, computed initially and again only when entries are removed; previews stay deferred. Four literal menu keys exist in all ten languages. | Latency measurement and official Swift localization checker not run. |

The screenshot harness's layout call was updated to the pure interface. Its normal
demo geometry is unchanged; rendered screenshot verification is still macOS-only.

## Test-first record and local checks

Before changing product code, the following regression tests were added:

- `Tests/TappiTests/TileLayoutTests.swift`
- `Tests/TappiTests/PanelScreenTests.swift`
- `Tests/TappiTests/ThumbnailRequestTests.swift`
- `Tests/TappiTests/SessionSelectionTests.swift`
- Legacy-settings and screen-choice round-trip cases in `SettingsTests.swift`.

At that stage `git status --short` showed **only test changes** and
`git diff --check` passed. Source inspection established the pre-fix failures:
layout lacked any height limit, presentation hard-coded the main screen and had an
unsafe empty-screen subscript, capture chose main-screen scale, and the new pure
interfaces/optional setting did not exist. The initial tests would not compile
against the original interfaces; this is an expected, **unexecuted** red state,
not a verified failing regression run. The very-narrow-screen regression was
added before correcting the additional 92%-margin edge case found during review.

The user explicitly prohibits builds/execution on this Linux server without
Swift/Xcode/AppKit. Therefore no Swift test was run before or after the fix, no
release build or screenshot renderer was run, and no CI-green or 1–2-ms claim is
made. This prevents the requested executed red/green TDD proof and runtime QS.

Local static review checked production call sites, session transitions, geometry,
settings encoding/decoding and capture cache/in-flight handling. The localization
search found all **40 additions** (four keys in ten language files), with literal
code references and no new placeholders. This does not replace the official
checker's plist lint. Final `git diff --check` passed.

## Required macOS / review follow-up

### Review correction: reflow after close/quit

The reported regression was confirmed in `SwitcherPanel.present`: removing only
tile slots left `panelSize` and `columns` unchanged. It now calls the pure
`TileLayout.reduceCount` transition, which recomputes geometry only when the entry
count decreases. The session retains its original tile-width/column settings,
chosen `visibleFrame`, backing scale and already-truncated window list. Initial
presentation and ordinary selection changes do not recompute layout.

Four regression cases were added to `TileLayoutTests` before this correction:
three windows reduced to two remove the unused column; removing an app's windows
removes empty rows; fewer windows restore original tile size; a truncated initial
layout stays unchanged until removal and excluded entries never return. Before
the fix, source inspection confirmed the old slot-removal path and the absence
of the new transition. The expected red state was not executed (the new tests
would not compile before the transition existed). Linux restrictions also prevent
a post-fix Swift test run; no executed red/green proof is claimed.

Run `swift test --filter TileLayoutTests` on macOS, then the existing release
build/test checks. Manually verify W and Q shrink and recenter the panel on its
original screen, including after removal during the show delay. `git diff --check`
is the available local whitespace check.

1. Read the full online thread and open PRs; reconcile any unavailable decisions.
2. Run relevant tests on macOS:

   ```sh
   swift test --filter 'TileLayoutTests|PanelScreenTests|ThumbnailRequestTests|SessionSelectionTests|SettingsTests'
   swift scripts/check-localizations.swift
   ```

3. Run existing macos-15 `build.yml` checks: warning-free
   `swift build -c release`, its “Fail on warnings” step,
   `swift test -c release` and bundle assembly. CI was not triggered here.
4. On a Mac with a 2x laptop display and 1x external display, test all three menu
   settings with focus and mouse on different monitors, including left/below/above
   placement. Confirm centered containment in the selected `visibleFrame`.
5. Use 320-pt tiles, four columns and 20+ windows, then enough windows to force
   truncation. Click every visible tile, cycle in both directions with Tab and
   arrows, commit, close an earlier/selected tile and quit an app with multiple
   tiles. Check that selection stays on the intended surviving window, omitted
    windows never become targets, the screen stays fixed and the panel reflows
    and recenters after each close/quit.
   Repeat with show delay 120 ms and sticky sessions; verify Escape/cancel.
6. Reopen quickly on a different-scale display while a capture is pending and
   within the four-second cache TTL. Check capture dimensions use the current
   panel scale and an older capture does not replace the newer preview.
7. Check a non-default pre-change settings file without `panelScreen`, restart,
   and confirm all preferences and active-screen default; then test persistence of
   each menu choice. Check screen unplugging and empty-screen fallback.
8. Compare before/after latency using
   `TAPPI_DEBUG=1 /Applications/Tappi.app/Contents/MacOS/Tappi`, with a dozen windows
   and zero show delay. Record actual `visible after … ms` samples.
9. Verify ordinary layouts visually; run `scripts/screenshots/render.sh` on macOS
   for the repository's prescribed rendered-image check.

Changes remain uncommitted in the supplied workspace. No production deployment,
production data change, release, signing, push or merge was performed.
