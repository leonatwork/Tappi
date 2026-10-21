# Issue #13 handover

## Basis and constraints

- The initial checkout was clean at `58bb856ee68f2acf4409d63f8f95173cde6162d8`,
  identical to `origin/master`. Local `origin/HEAD` and `.github/workflows/build.yml`
  identify `master` as the default branch; `origin/main` does not exist locally.
  The issue's `origin/main` requirement is interpreted as the default-branch baseline.
- GitHub access (`gh`) is denied by the harness. Additional issue comments, current
  remote metadata, open PRs and their dependencies could not be inspected. Acceptance
  criteria come from the complete issue description supplied in the task.
- No `AGENTS.md` or `CLAUDE.md` exists in this checkout. `CONTRIBUTING.md` was read;
  access to parent-directory rule files is denied.
- No branches were checked out or created, and no PR code was used. There were no
  commits, pushes, PR creation, merges, releases, deployments or production changes.

## Implementation and acceptance criteria

`AX.windows` returns `nil` for `.cannotComplete`, preserving its previous behavior
for other errors. Enumeration carries unresponsive pids to the merge. The adapter
checks current `regularApps()` again before applying the background snapshot, so
terminated apps cannot be retained or reintroduced by stale enumeration results.

`WindowMerge.merge` is pure and generic over window identity, pid and payload.
The AX adapter reuses existing `WindowEntry` objects and their thumbnail caches.

| Criterion | Implementation and regression coverage |
| --- | --- |
| AC-1 | Preserve all timed-out app entries, their relative MRU positions and last values; regression cases cover interleaved apps and multiple windows. |
| AC-2 | Recovery updates entries in place; a regression case covers repeated timeouts. |
| AC-3 | An empty successful snapshot removes entries; a regression case covers this after a timeout. |
| AC-4 | `appTerminated` still removes entries immediately; the adapter filters current running pids. Pure tests cover absence of the pid on the next refresh and already-removed entries during an in-flight timeout. The notification/AX integration needs macOS verification. |
| AC-5 | Cold starts sort responding windows by z-order, including offscreen windows; an all-timeout start remains empty. |
| AC-6 | Twelve XCTest cases in `Tests/TappiTests/WindowMergeTests.swift`, using `@testable import Tappi`. Existing macos-15 CI already builds, rejects warnings and runs release tests. A green CI run has not been observed. |
| AC-7 | Refresh/merge remains on the existing asynchronous refresh path. Hotkey code, 250 ms timeout and 2.5 s sweep are unchanged. The 1–2 ms latency needs macOS measurement. |

Positions mean preserved MRU order: removing another closed window can shift an
absolute array index. Existing focused-window promotion remains unchanged.

## Verification and remaining evidence

Tests were written before the production fix. No build or code execution is allowed
on this Linux server. Consequently neither a failing regression run before the fix
nor a passing run afterward was observed. Before implementation, the pure test API
did not exist and the old merge discarded every entry absent from the snapshot,
including timed-out windows. This source inspection is not a runtime red/green proof.

Static review covered all new files, the AX call site, pid filtering, object reuse,
and unchanged refresh/hotkey scheduling. `git diff --check` passed.

On macOS, run the focused regression suite with
`swift test -c release --filter WindowMergeTests`, then the existing CI checks:
`swift build -c release` (no warnings) and `swift test -c release`.

For integration evidence, establish an MRU order with windows from two apps, pause
one disposable app using `kill -STOP <pid>`, wait through multiple sweeps, and check
that its windows stay visible in order. Resume it with `kill -CONT <pid>` and verify
the same order on recovery. Check a successful empty response by closing its windows,
and check termination after a timeout. Always resume the paused app after testing.
Compare `visible after … ms` before and after using
`TAPPI_DEBUG=1 /Applications/Tappi.app/Contents/MacOS/Tappi`.
