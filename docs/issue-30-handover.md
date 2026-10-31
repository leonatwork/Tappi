# Issue #30 — handover

Issue: https://github.com/leonatwork/Tappi/issues/30

## Baseline and available evidence

The checkout started clean at `f82b389ebd5300830235f2fb57c3740d287ca7bf`,
identical to `origin/master`. Repository metadata has `origin/HEAD ->
origin/master`; the build workflow also targets `master`. There is no local
`origin/main`, so the task's literal baseline name cannot be satisfied. Work
uses the checked-out default-branch commit. No branches were created or checked
out, and no changes from open PR branches were used.

GitHub CLI access is denied by the environment's tool policy. The full thread,
comments, open PRs and possible dependencies could not be checked. Acceptance
criteria below come from the complete issue description supplied in the task;
no claim is made about additional decisions in inaccessible comments.
`CLAUDE.md` and `AGENTS.md` are absent from this checkout. `CONTRIBUTING.md`,
the package, existing XCTest style and build workflow were reviewed.

## Implementation and acceptance criteria

- **AC-1:** The startup gate precedes status-item creation, diagnostics reset,
  settings access, permission prompts, orphan repair and event-tap startup.
  Rejected/waiting copies do not own the lifecycle. Their termination skips
  `SwitcherController.shared`, avoiding its initialization side effects.
- **AC-2:** Menu restart uses a unique temporary handover directory (mode 0700),
  passed through Launch Services arguments. The replacement announces readiness
  only in its waiting path. The old copy terminates only after a successful launch
  callback, readiness, a live replacement and atomic handover acceptance.
  Launch failure, cancellation or readiness timeout leaves the old copy active.
  Repeated restart clicks and callbacks from expired requests are ignored.
  The replacement checks running peers again on every poll and initializes only
  after they have exited. Acceptance and timeout atomically compete to create
  one symlink; cancellation cannot be followed by acceptance, and acceptance
  cannot be undone by a racing timeout. The replacement removes the handover
  directory on ordinary completion; aborted launch attempts also remove it.
- **AC-3:** `InstanceLifecycle` contains pure startup, termination and restore
  decisions. New XCTest coverage includes ordinary duplicates, restart success,
  readiness versus launch callback, dead replacement, timeout, deadline-boundary
  exit, ownership/forced restore, argument validation and handover arbitration.
  Handover tests use temporary files only, never real system shortcuts/settings.
- **AC-4:** Warning-free release build and passing existing tests remain
  **unverified**, because this Linux host lacks Swift/Xcode/AppKit and the task
  expressly prohibits building/running tests here.
- **AC-5:** SIGTERM/SIGINT/SIGHUP handlers are installed only after admission and
  use the same guarded cleanup as normal termination. Waiting/rejected copies
  retain default signal behavior and never install a handler that restores keys.
  `SystemSwitcher.restore(force:)` independently rejects non-owners; force still
  permits explicit orphan/manual repair by the admitted instance. Normal cleanup
  restores only shortcuts suppressed by this run.

### Timeout decision

Use the issue's assumed **5 seconds for launch/readiness**, including Launch
Services time, measured with system uptime. An accepted handover extends the
replacement's deadline by **5 seconds**, to a maximum of 10 seconds from the
original request, reserving additional time for parent cleanup/exit. This avoids
discarding an accepted replacement at the readiness
deadline while the parent is cleaning up. A readiness timeout retains the old
copy; an exit timeout discards the waiting replacement if a peer still runs.
The issue leaves the duration open; a strict five-second *total* interpretation
would differ from this explicit two-phase choice.

## Verification and remaining macOS checks

Tests were added before production changes. Source inspection at that point
confirmed that `InstanceLifecycle` and `RestartRequest` did not exist, so the
new tests would initially fail to compile. The additional arbitration tests
were likewise added before their production methods. **No executed red/green
test result is available.** Static review covered the callback/readiness ordering,
ownership guards, cancellation/acceptance race and late callbacks.
`git diff --check` passed; the three new files also passed individual
`git diff --no-index --check /dev/null <file>` whitespace checks.

Required on macOS 14+ before acceptance:

1. Run `swift test -c release --filter InstanceLifecycleTests`, then
   `swift test -c release` and `swift build -c release`; apply the build workflow's
   warning check. Run `swift scripts/check-localizations.swift` as prescribed
   by the repository (no localization keys were added).
2. With command-modifier replacement enabled, permissions granted and Tappi
   operational, launch a second copy (installed app and build copy). Verify
   only the original remains, its event tap and suppressed shortcuts remain
   intact, and settings are not written by the rejected copy.
3. Restart through both menu entries, including rapid repeated clicks. Verify
   a changed PID, exactly one instance and working Tappi command-tab after
   readiness. Verify successful handover removes its temporary directory.
4. Delay replacement launch/readiness beyond five seconds: the original PID
   and shortcut ownership must remain. Also exercise launch failure, acceptance
   near the deadline, delayed parent exit and late callbacks. Check that an
   expired attempt cannot terminate the original during a later restart.
5. Deliver SIGTERM, SIGINT and SIGHUP individually to a waiting replacement;
   the original's shortcuts must stay suppressed. Check owner termination
   restores its suppression, and explicit orphan/manual repair still works.

Full-thread/PR dependency review remains outstanding due to blocked access.
No known open-PR dependency was incorporated. Changes are uncommitted; nothing
was pushed, deployed or merged.
