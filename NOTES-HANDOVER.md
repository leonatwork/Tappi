# Issue #12 — handover

Issue: https://github.com/leonatwork/Tappi/issues/12

## Baseline and scope

The checked-out commit is `58bb856ee68f2acf4409d63f8f95173cde6162d8`,
identical to the local `origin/master` reference. This repository uses
`origin/HEAD -> origin/master`, and `build.yml` targets `master`; there is no
local `origin/main`. As clarified in the review, `origin/master` is the intended
baseline. No other branch was checked out and no PR changes were incorporated.

The restore menu action now calls `SystemSwitcher.restore(force: true)` followed
by `SystemSwitcher.apply()`. Forcing restoration bypasses the ownership guard
when another tool disabled the shortcuts. Applying the current policy afterwards
keeps the system state consistent with Tappi's settings and readiness.

## Acceptance criteria

The supplied issue description establishes the following criteria:

- **AC-1:** With externally disabled shortcuts and no policy requesting Tappi
  suppression (the reproduction uses the option modifier), the action enables
  symbolic hot keys **1, 2, 27 and 28**. The existing forced restore iterates over
  all four keys. Runtime confirmation remains outstanding.
- **AC-2:** Reopening the menu hides the restore item after successful restoration.
  The existing menu rebuild reads the current shortcut and suppression state.
  Runtime confirmation remains outstanding.
- **AC-3:** The item remains hidden when `isSuppressed == true`. The existing
  visibility condition is unchanged; runtime confirmation remains outstanding.
- **AC-4:** `swift build -c release` must be warning-free, including the workflow's
  “Fail on warnings” check. Not verified on this Linux server.

**AC-1 qualification:** Its literal unconditional final enabled-state requirement
conflicts with the explicit UX decision allowing `apply()` to suppress the keys
again when command-modifier replacement is configured and Tappi is ready. The
implementation follows that decision: under replacement policy, forced
restoration is followed by permitted re-suppression. The menu item is then hidden
because `isSuppressed` is true. Always leaving all four keys enabled in that
configuration would contradict the specified policy re-evaluation.

## Regression-test decision

No new XCTest is included. The issue's **QS und Nachweis** section explicitly
states that a unit test is not useful without abstracting the private CGS API.
The existing XCTest style (`import XCTest`, `@testable import Tappi`) was reviewed.
An isolated behavioral test of this action would require an API seam and control
over global settings/readiness dependencies. Directly invoking the current API
would instead change the host Mac's system-wide shortcuts. Adding that abstraction
for this two-call fix would expand the requested minimal scope; a source-text
assertion would not prove shortcut restoration or menu behavior.

Consequently, the requested test-driven red/green runtime proof is not supplied.
The later review explicitly permits this documented test omission. Verification
uses source review here and requires the macOS checks below before acceptance.

## Verification

- Before the fix, source inspection confirmed that the menu appears only for
  `!systemShortcutsEnabled && !isSuppressed`, while the action called unforced
  `restore()`. Its ownership guard therefore returned without enabling any keys.
- After the fix, source inspection confirms forced restoration precedes policy
  re-evaluation. `SystemSwitcher.apply()`, `suppress()`, the visibility condition,
  dependencies and localized strings are unchanged.
- `git diff --check` passed after the fix.

### Not verified

- The full issue thread, comments, existing PRs and potential PR dependencies:
  the environment's permission policy blocks GitHub CLI access. Only the issue
  description and review findings supplied in the task were available.
- `CLAUDE.md`: absent from this checkout, as is `AGENTS.md`.
  `CONTRIBUTING.md`, the package, existing tests and build workflow were read.
- Swift tests, release build, CI warning check and manual macOS behavior: the
  server is Linux without Swift/Xcode/AppKit, and the task explicitly prohibits
  building or running the app/tests here. No runtime failure/pass or CI success
  is claimed.

### Required macOS follow-up

1. With Tappi using the option modifier, externally disable all four symbolic
   hot keys (1, 2, 27, 28) and open the menu. Confirm the restore item appears.
2. Click it; verify all four keys are enabled
   (`SystemSwitcher.systemShortcutsEnabled == true`) and actual ⌘Tab works.
3. Reopen the menu and confirm the restore item has disappeared.
4. With command-modifier replacement enabled and Tappi ready, confirm
   `isSuppressed == true` and the restore item stays hidden. Policy-driven
   re-suppression after restoration is explicitly permitted by the issue.
5. Run `swift test -c release` and `swift build -c release`, including the
   `build.yml` “Fail on warnings” check on macOS-15.

Changes remain uncommitted. Nothing was pushed, deployed or merged.
