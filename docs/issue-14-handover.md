# Issue #14 — handover

Issue: https://github.com/leonatwork/Tappi/issues/14

## Baseline and binding requirements

The initially clean checkout is `967e608fbc5cc456e178d847556060e45cc670ea`,
identical to local `origin/master`. `origin/HEAD`, branch tracking and
`.github/workflows/build.yml` identify `master` as the default branch. There is
no local `origin/main`; the literal baseline requirement conflicts with the
available repository metadata. Work uses only this supplied default-branch
commit. No other branch was checked out or incorporated.

GitHub CLI access is denied by the harness permission policy. Consequently the
live issue thread/comments, open PRs, remote freshness and CI status could not
be verified. The supplied structured issue and resolved decisions are the
available acceptance criteria. `CLAUDE.md` and `AGENTS.md` are absent from this
checkout. `CONTRIBUTING.md`, current code/tests, localization checker, screenshot
renderer and build workflow were reviewed; `kb ask` confirmed the architecture.

The current instruction to implement the complete issue without creating
branches, commits, pushes or PRs supersedes the issue's three sequential
branches/draft PRs. All three implementation packages are included as local,
uncommitted changes. Issue #18's test target and CI are already on the baseline
(commit `cafdaef`, PR #26); this solution has no known open-PR dependency. The
inability to inspect live PRs leaves overlap/dependency verification outstanding.

### Layout conflict resolution

AC-5 explicitly requires ANSI positions 13/12 for a current non-Latin layout.
The issue also states that the ASCII-capable input source is authoritative,
although that source can remember the last Latin layout. These requirements
conflict when, for example, Russian follows Dvorak. The implementation gives
AC-5 precedence: translate the current layout to establish whether each Latin
letter exists, use the ASCII-capable layout to locate that letter when present,
and otherwise fall back independently to 13/12. Missing layout data also falls
back. A unit test covers Russian with a remembered Dvorak ASCII source.

The structured criteria supersede the original description's immediate-Q quit
behavior. Q now requires two physical presses; automatic key-repeat events
neither arm nor confirm a quit request. There is no confirmation timer.

## Acceptance criteria and evidence

All implementation statuses below are source-reviewed, **not runtime verified**.

| Criterion | Implementation / regression coverage | Remaining evidence |
| --- | --- | --- |
| AC-1: AZERTY W closes; A/Z do nothing | `SwitcherKeyMapTests` checks W at 6, Q at 0 and no action at ANSI 12/13; the controller routes the cached close action to the existing window-close path. | Real French keyboard/layout check. |
| AC-2: AZERTY/Dvorak Q quits only on the second press for unchanged selection; first press shows a hint | Mapping tests cover both layouts. `QuitConfirmationTests` checks first/second/third press, changed window within the same app, missing target and repeat events. The controller shows the panel immediately if a show delay is pending. | Actual app termination and visible hint. |
| AC-3: QWERTY/QWERTZ/Colemak W stays unchanged; Q uses confirmation | Fixtures for all three layouts preserve 13/12; every quit action passes through the same pure state machine. | Physical layout checks. |
| AC-4: layout changes take effect without restart by next opening | `KeyboardLayoutCache` rebuilds on `kTISNotifySelectedKeyboardInputSourceChanged`, using immediate main-run-loop delivery; a mapping regression verifies old bindings disappear on rebuild. | TIS notification delivery, including rapid layout-change/reopen sequences. |
| AC-5: non-Latin layout uses ANSI fallback | Current-layout letter availability is checked independently of the remembered ASCII source; tests cover Cyrillic, empty data and one missing letter. | Russian after French/Dvorak, plus input-method behavior. |
| AC-6: Backspace 51 and forward-delete 117 close | Both are unconditional cached close actions; tests protect them from remapping. | Both actual keys, including Fn-Delete on Mac keyboards. |
| AC-7: other key, selection change, Esc, commit or session end discards request and hint | The pure machine handles other keys, target changes and session end. Controller keyDown clears before every non-Q action/default; flagsChanged clears for modifier keys in holding/sticky modes; mouse selection tracks window identity; close, quit, stop and end clear the request. Commit/Esc/watchdog/outside click use end. Same-window hover preserves it. | Holding/sticky/delayed sessions, mouse hover/click and live exclusion changes. |
| AC-8: cached O(1) lookup; no TIS/translation in tap; ~1–2 ms latency; hint in all ten languages; localization lint clean | Source inspection confines TIS/UCKeyTranslate to cache startup/notification methods. Tap does one dictionary lookup. `switcher.quitConfirmation` is present in all ten tables and tested through each localizer. | Measured latency, executed localization checker and green macos-15 CI. |

Both READMEs document Backspace/forward-delete, layout-dependent letters, ANSI
fallback, two presses, repeat protection and request cancellation.

## Implementation review notes

- Translation scans virtual keycodes 0–127 with zero modifiers and disabled
  dead-key state. Matching is case-insensitive. Fixed navigation/above-Tab keys
  are excluded from letter remapping; their existing handling stays authoritative.
- Cache initialization and distributed layout notifications run on the main
  run loop, as does the tap. There are no lazy TIS lookups at session start or
  asynchronous cache writes racing event processing.
- Quit confirmation stores `ObjectIdentifier` of the selected `WindowEntry`,
  rather than an index or app PID. Reindexing surviving windows cannot confirm
  a different window accidentally. Removing/excluding the selected entry clears
  its request; same-window mouse hover does not.
- The hint label is prebuilt and localized at startup/settings notifications.
  Showing/hiding it does not look up strings or rebuild tile geometry in the
  callback. A 44-point footer budget is reserved before fixing session capacity;
  it is added to the displayed panel only while the hint is visible. Tile drawing,
  hit testing, selection offsets and reflow keep the same content coordinates.
  Reserving this budget can shrink/truncate tiles slightly earlier on very short
  screens; showing the hint never removes a tile from the prepared session.
- Existing close/quit list removal, selection correction and layout reflow are
  reused. No new AX calls were introduced. Carbon is a native macOS framework,
  linked explicitly; no third-party dependency was added.

## Test-first work and verification limits

`SwitcherKeyMapTests`, `QuitConfirmationTests` and the ten-language hint regression
in `InterfaceLanguageTests` were added before production code. Pre-fix source
inspection found no mapping/state-machine APIs or hint key. The existing code
necessarily maps AZERTY A/Z to quit/close, swallows delete and quits on the first
Q. These are source-level regression observations, **not an executed red run**.
The explicit Linux/no-Swift execution restriction prevents proving correctly
failing tests before the fix and passing tests after it on this server.

`git diff --check` passed. Static review checked the new source files, all event
delegate call sites, cache lifetime/translation ownership, every confirmation
cancellation path, tile reflow/offsets and the new key in all ten language files.
No Swift build/test, app, localization script or screenshot renderer was run.
The required warning-free build, native strings-file lint and CI result remain
unverified; the existing macos-15 workflow already runs those build/test gates.
Its localization checker prints an `OK` summary on success, so “no messages” in
AC-8 is interpreted as no problem reports rather than literally empty stdout.

## Required macOS follow-up

1. Run focused tests:
   `swift test --filter 'SwitcherKeyMapTests|QuitConfirmationTests|InterfaceLanguageTests'`.
   For an executed red/green record, run the new regression tests against the
   baseline in a separate disposable checkout, then against this patch; the
   extracted APIs are absent at baseline, so the initial red includes compilation
   failures. A real-key baseline reproduction supplies the behavioral evidence.
2. Run `swift scripts/check-localizations.swift`, `swift build -c release` with
   the existing warning check, and `swift test -c release`. Obtain green
   `.github/workflows/build.yml` on macos-15, including bundle assembly.
3. Activate French, Dvorak, German and Russian in turn. In an open switcher test
   labelled W, Q once/twice, A, Z, Backspace and forward-delete. Switch Russian
   on after French/Dvorak and check ANSI 13/12. Switch layouts rapidly and reopen
   without restart to verify notification timing. Check QWERTY/Colemak too.
4. After first Q, try a different key, a modifier change, arrow/Tab navigation,
   same/different-window hover, mouse activation/close, Esc, Return/Space,
   modifier release, outside click and session end. Reopen and verify Q is a first
   press again. Hold Q through autorepeat: it must not terminate the app. Check
   delayed and sticky sessions and selected-window removal through exclusions.
5. Check the hint in all ten languages, including minimum-width tiles and a
   short screen. Confirm full readable text, selection highlight alignment,
   mouse hit testing and reflow after close/quit. Run
   `scripts/screenshots/render.sh` as required by CONTRIBUTING.md and review the
   English/German README images; regeneration is pending due to the Linux limit.
6. Measure before/after with
   `TAPPI_DEBUG=1 /Applications/Tappi.app/Contents/MacOS/Tappi` and compare
   `visible after … ms` (~1–2 ms target). This performance claim is not yet proven.
7. Read the live issue comments and open PRs before review/merging to reconcile
   any decisions or overlap unavailable in this environment.

Changes remain uncommitted. No branch creation, push, PR creation, merge,
release, signing/notarization, deployment or production-data access occurred.
