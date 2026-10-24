# Issue #16 — handover

Issue: https://github.com/leonatwork/Tappi/issues/16

## Baseline, requirements and limitations

HEAD was clean and equals the local `origin/master` at
`afd0d74234702728962fb2415656e56b375d5782`. `origin/HEAD` points to
`origin/master`; `.github/workflows/build.yml` targets `master`. The literal
`origin/main` requirement conflicts with this repository's default-branch name.
The implementation uses the checked-out default-branch commit. No branch was
created or checked out, and no open-PR branch was used or cherry-picked.

GitHub CLI access is denied by the environment's permission policy. The full live
threads of #16/#11, comments, current open PRs and remote freshness could not be
verified. Requirements follow the supplied structured issue, with the original
description supplying technical details. The knowledge base confirms Leon's
decisions: #11 plus #16 together, settings.json and README only, presets only for
list B. `AGENTS.md` and `CLAUDE.md` are absent from the checkout.
`CONTRIBUTING.md`, package, existing tests, settings callers and CI were reviewed.

Issue #11 is already part of the baseline: its tip commit identifies merged PR
#22, and the code includes tolerant per-field decoding, backup-before-save,
in-memory tests and both README updates. No outstanding #11 PR dependency is
needed for this implementation. Its existing acceptance mapping and outstanding
manual backup checks are in [issue-11-handover.md](issue-11-handover.md).
Live PR status remains unverified. `StatusItem.swift` is untouched.

## Acceptance criteria

| Criterion | Implementation / evidence | Status |
| --- | --- | --- |
| AC-1: list A hides all windows in both scopes | `WindowEntry.bundleID` comes from the app snapshot. The pure `WindowStore.sessionList` filter is used by both shortcuts. Tests cover multiple windows, case differences, missing IDs and both scopes. | Implemented; runtime pending. |
| AC-2: removing an exclusion restores stored MRU positions without restart | Filtering never removes/reorders backing entries. Settings reload rebuilds the exclusion set; tests remove an ID and check the original order returns. Normal focus-driven MRU updates still apply. | Implemented; runtime pending. |
| AC-3: foreground list-B app receives shortcuts without a Tappi panel | Idle tap decision returns false for both Tab and above-Tab before `begin`. Tests cover command/option/control and Shift/Control variants. | Implemented; runtime pending. |
| AC-4: system shortcuts restored for foreground list B, suppressed for other apps when replacing | Activation immediately caches normalized bundle ID/PID and calls `SystemSwitcher.apply()` before AX work. Both tap and system policy use the same cache/set. Tests cover foreground transitions, readiness, replacement off and other modifiers. | Policy implemented/tested in source; actual CGS enabled state pending Mac verification. |
| AC-5: shortcuts enabled on termination, including foreground list B | Existing normal-termination and signal handlers force restoration of keys 1, 2, 27 and 28. | Existing behavior preserved; runtime pending. |
| AC-6: legacy/missing-key files retain other settings and supply presets | New fields participate in #11's per-field decoder. List A defaults empty; list B has the five specified IDs. Tests check legacy files, every missing key, invalid/null values, malformed arrays and explicit empty overrides. | Implemented; runtime pending. |
| AC-7: decoding, filtering and pure tap-decision tests, case-insensitive IDs, no workspace/AX calls in tap callback | Extended `SettingsTests` and new `AppExclusionTests`. Normalization and set creation occur on settings reload/activation. The new tap decision does one cached set-membership lookup; the session-list path now also uses cached PID instead of `NSWorkspace`. | Source-reviewed; test execution pending. |
| AC-8: #11 complete, both READMEs document fields/presets, no new UI strings | Existing #11 implementation retained and its tests expanded to both fields. Both READMEs describe defaults, independent lists and menu-triggered reload. | Documentation complete; inherited #11 runtime/backup and CI checks pending. |

The structured scope supersedes the original description's exclusion of #11 and
optional menu/localization work. Default list B is Microsoft Remote Desktop /
Windows App (`com.microsoft.rdc.macos`), Parallels Desktop
(`com.parallels.desktop.console`), VMware Fusion (`com.vmware.fusion`), UTM
(`com.utmapp.UTM`) and Citrix Viewer (`com.citrix.receiver.icaviewer.mac`).
Already-running sessions are not cancelled on activation of a list-B app; the
pure decision retains session handling. Actual key routing during such an
activation still requires manual macOS verification.

## Test-first evidence and local review

The `SettingsTests` extensions and `AppExclusionTests` were written before product
changes. A pre-fix search of `Sources` found none of the new settings fields,
`AppRules`, static filtering seam or `shouldSuppress` seam. At that stage the
tests could not compile because these interfaces were absent; the previous code
also unconditionally started Tappi for the shortcut and had no app filter.
This is **static red-phase evidence, not an executed failing test run**.

This Linux server has no Swift/Xcode/AppKit and the task explicitly forbids builds
or execution here. No Swift tests, localization script, release build or app were
run. No executed red/green proof, warning-free build, green macos-15 CI or measured
hotkey latency is claimed. These verification criteria cannot be completed here.

`git diff --check` passed. Manual source review covered decoder/encoder field
coverage, cache initialization and reload ordering, startup/activation caching,
shared tap/system policy, preservation of backing entries, existing quit cleanup
and unchanged window filters. New tests exercise pure policy/filtering and
in-memory decoding; they do not install a tap, change system shortcuts or read
the user's settings. AX elements in filter fixtures are only inert references;
no AX window query/focus call is made.

## Required macOS follow-up

1. Run `swift test -c release --filter SettingsTests` and
   `swift test -c release --filter AppExclusionTests`. For red-phase confirmation,
   apply the regression tests to the baseline in a separate disposable checkout:
   the absent new interfaces must produce compilation failures. A behavioral
   red/green execution of the new seams was not captured by this run.
2. Run the prescribed `swift build -c release` warning-free and
   `swift test -c release`; obtain the existing `build.yml` macos-15 result.
3. With a disposable local settings profile, exclude an app with multiple windows.
   Open the menu to reload, verify both shortcuts omit its windows, remove the ID,
   reload and confirm the stored MRU order returns without restarting. Include a
   case-different bundle ID and minimized/hidden/other-Space windows.
4. Put UTM or a test app in list B and bring it forward. Verify no Tappi panel and
   `SystemSwitcher.systemShortcutsEnabled == true` for keys 1, 2, 27 and 28.
   Bring an ordinary app forward and verify Tappi replacement resumes. Repeat
   with above-Tab/Shift variants and option/control modifiers. Verify a held or
   sticky session is not cancelled by activation of a list-B app.
5. Quit normally and via a handled signal while list B is foreground; confirm
   system shortcuts remain enabled. Check the #11 invalid-file startup/reload,
   exact-byte backup and failed-backup preservation cases described in its handover.
6. Measure before/after latency with
   `TAPPI_DEBUG=1 /Applications/Tappi.app/Contents/MacOS/Tappi`; confirm approximately
   1–2 ms and passthrough events logged with `swallow=no` when delivered to the tap.

Changes remain uncommitted. Nothing was pushed, deployed or merged; no PR was
created, as explicitly requested for this run.
