# Issue #16 — handover

Issue: https://github.com/leonatwork/Tappi/issues/16

## Baseline, requirements and access limits

The initially clean checkout is `cafdaef37126f3745eaea40e88b5fe228c903459`,
identical to local `origin/master`. `origin/HEAD`, branch tracking and
`.github/workflows/build.yml` identify `master` as the default branch. There is
no local `origin/main`; the literal baseline name conflicts with repository
metadata. Work stays on the supplied default-branch commit. No branches were
created or checked out, and no open-PR branches or cherry-picks were used.

GitHub CLI access is denied by the environment's permission policy. The live
issue thread/comments, current open PRs, remote freshness and CI status could
not be checked. The supplied structured issue and resolved decisions are the
available binding requirements. `AGENTS.md` and `CLAUDE.md` are absent from the
checkout. `CONTRIBUTING.md`, existing code/tests and the build workflow were read;
the requested `kb ask` also confirmed the architecture and hotkey constraints.

Issue #11 is already included in this baseline by commit `afd0d74` / PR #22.
Its full issue description is preserved in that commit message, and its
implementation/handover were reviewed. It is therefore an existing prerequisite,
not an open-PR dependency to incorporate. No changes to `StatusItem.swift`, UI
strings, dependencies or CI infrastructure are needed.

The structured issue supersedes the original description's conflicting scope:
#11 is in scope, the field is `excludedApps`, list B has presets, and there is no
menu UI. The explicit Linux restriction prevents the otherwise requested
executed test-first red/green proof and macOS quality gates here.

## Acceptance criteria

| Criterion | Implementation and evidence | Status |
| --- | --- | --- |
| AC-1: list A hides every app window for both shortcuts | `WindowEntry.bundleID` comes from app snapshots; `WindowSessionList.make` filters both scopes using the cached policy. Tests cover all window states, case-insensitivity and unknown IDs. | Implemented; runtime pending. |
| AC-2: removing an exclusion restores MRU without restart | Filtering never removes/reorders `WindowStore.entries`; existing menu reload rebuilds the cached policy. A subsequent session uses the retained order. Test filters and restores the same input. | Implemented; runtime pending. |
| AC-3: list B does not open a panel or swallow hotkeys | The controller guards session creation with the tested pure `shouldHandleKeyDown` decision. Tab, both above-Tab keycodes, Shift/sticky flags and all modifiers are covered. | Implemented; runtime pending. |
| AC-4: system shortcuts enabled for list-B foreground, suppressed again for other apps | Startup seeds normalized foreground ID/PID; activation updates them and calls `SystemSwitcher.apply()` before AX observer/focus work. The pure policy combines settings, readiness and foreground membership. | Policy unit tests supplied; actual CGS state pending. |
| AC-5: quitting in a list-B app leaves system shortcuts enabled | Existing normal-termination and signal handlers call `restore(force: true)` for all four symbolic hotkeys. | Existing implementation retained; manual pending. |
| AC-6: legacy or incomplete JSON preserves other settings and defaults each list | The #11 decoder gains per-field `[String]` fallbacks from `Settings()`. A defaults to `[]`; B defaults to the five specified IDs. Explicit empty arrays disable defaults; invalid/mixed-type arrays default only that field. | Regression tests supplied; execution pending. |
| AC-7: unit tests and no foreground API calls in the tap callback | `AppExclusionPolicyTests`, extended settings/filter/session tests; normalized sets rebuilt at settings changes. The tap decision does one cached Set lookup, no NSWorkspace/AX lookup. `sessionList` now uses cached PID instead of querying NSWorkspace. | Source-reviewed; tests pending. |
| AC-8: #11 complete and both READMEs explain lists/defaults | Existing tolerant decoder, backup-on-save protection, NSLog errors and tests are retained. Both READMEs document JSON configuration, defaults, reload, MRU and independent behavior. | Implemented; #11 filesystem/manual and CI evidence remain pending. |

### #11 acceptance criteria retained

- Missing, null or invalid fields default individually; `{}` equals `Settings()`.
  Existing exhaustive field tests now include both new arrays.
- Unknown keys are ignored; encoding/decoding preserves every field, including
  user-supplied array spelling/order and explicit empty arrays.
- An unreadable document is logged at startup/reload. Loading does not rewrite
  it; the next save copies its original bytes to `settings.json.bak` before the
  atomic settings write. Backup failure prevents overwriting the original.
- Runtime failed reload followed by mutation still validates/backs up at the
  write boundary. This does not depend on the recorded modification date.
- Backup behavior remains a manual check, as #11 explicitly requested
  filesystem-free unit tests. See `docs/issue-11-handover.md` for its scenarios.
- The existing macos-15 workflow runs localization lint, release build, warning
  detection, release tests and bundle assembly. Its green result is unverified.

## State and keyboard edge cases

If filtering removed the current window, a forward session selects the first
remaining candidate, not index 1. One remaining candidate can be activated when
it is not the current window. Reverse cycling still begins at the last tile.
Existing callers/tests keep the original single-current-window rule by default.

Adding list-A exclusions during a live/delayed session removes matching entries
and preserves the selected window's identity (or selects its successor/last
remaining tile). An empty session ends. Presented panels reflow through the
existing `present()` layout path; delayed panels reflow when presented. Removing
an exclusion affects the next session, without rebuilding the MRU store.
Close/quit actions retain the existing identity correction and layout reflow.

The original issue requires ongoing sessions not to be aborted when a list-B app
comes forward. Consequently AC-3 describes **starting** sessions: active holding
or sticky sessions keep their existing key handling until completion/cancel.
Activation still restores the system shortcuts immediately (AC-4), even during
an active session. Actual macOS symbolic-hotkey routing in this combination must
be checked manually; the unit test proves only the tap's pure decision.

No foreground or AX queries were added to the tap. Its close-window action now
dispatches `AX.close()` off the main loop, since that action is also reachable
from the tap. Focus already dispatches AX operations off-thread. The hotkey-start
path no longer queries NSWorkspace at all. Selection/layout behavior is covered
at the pure session/filter interface; actual AX close/focus remains a manual
check rather than adding host-window side effects to unit tests.

## Test-first work and verification

Tests were edited/added before production code. Pre-fix source inspection found
no app-list fields, `AppExclusionPolicy` or `currentWindowIncluded` parameter.
The new tests therefore initially require absent APIs (compile-time red); the
existing filter also necessarily retains windows the new tests expect removed.
This is source-level evidence, **not an executed failure or passing test run**.
Follow-up review added coverage for ordinary-app hotkeys, all preset IDs and
selection identity after filtering.

### Review follow-up: fast toggling before activation notification

Session start now compares the MRU head's identity with the first filtered
candidate through `SessionSelection.includesCurrentWindow`. It does not require
the notification-driven foreground PID to match: commit promotes synchronously,
while focus and the activation notification can still be pending.

Tests in `SessionSelectionTests` were added before this fix. They exercise four
alternating commits with two/three windows and an unchanged foreground PID, plus
an excluded MRU head with one/two remaining candidates and an empty list. With
the reviewed PID condition, the second toggle selects app B again instead of
returning to app A. This is source-level regression evidence; no Swift red/green
run is possible under the Linux restriction. `git diff --check` passed. On macOS,
run `swift test --filter 'SessionSelectionTests|SwitcherSessionTests|WindowSessionListTests'`
and manually repeat rapid press/release toggles before/after with `TAPPI_DEBUG=1`.

No Swift/app build, tests or localization script were executed on this Linux
server, in accordance with the explicit task restriction. `git diff --check`
passed. Source review checked decoder/encoder coverage, cached-policy rebuild
ordering, snapshot propagation, both keyboard scopes, initialization, live
selection/layout changes, foreground activation and existing termination paths.

### Required macOS follow-up

1. Run the focused tests:
   `swift test --filter 'SettingsTests|WindowSessionListTests|AppExclusionPolicyTests|SwitcherSessionTests|SessionSelectionTests'`.
2. Run `swift scripts/check-localizations.swift`, `swift build -c release` with
   the existing warning check, and `swift test -c release`; obtain green
   `build.yml` on macos-15, including bundle assembly.
3. In a disposable local profile, exclude a multi-window app and reopen the menu.
   Check Tab and the physical key above Tab (ANSI/ISO), reverse and sticky modes.
   Remove the exclusion and reload: verify retained MRU without restarting.
4. Exclude the current app: forward cycling must start at the first allowed
   window, including when only one other window remains. During a delayed/sticky
   session, add exclusions and check selected identity, reflow and empty-list end.
   Close and quit tiles; verify surviving selections/layouts and actual AX close.
5. Put a list-B app in front (also test mixed-case IDs). Check no new Tappi panel,
   unconsumed hotkeys and `SystemSwitcher.systemShortcutsEnabled == true`. Bring
   an ordinary app forward: suppression returns when ready/configured. Test an
   explicit empty list and option/control modifiers. Verify actual bundle IDs
   and remote keyboard routing for installed versions of the five preset apps.
6. Switch foreground to a list-B app during a holding/sticky session: it must
   not be cancelled; check modifier release, Escape and actual Tab routing.
   Quit normally and by a handled signal while such an app is frontmost; verify
   all four system shortcuts remain enabled.
7. Repeat #11's startup/runtime malformed-file and failed-backup checks in
   `docs/issue-11-handover.md`; confirm original bytes are preserved.
8. Compare before/after panel latency with `TAPPI_DEBUG=1`, targeting ~1–2 ms.

Changes remain uncommitted. No push, branch creation, PR creation, merge, release,
deployment or production-data access occurred.
