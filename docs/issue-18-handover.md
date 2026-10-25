# Issue #18 — core-rule tests and CI gates

Issue: https://github.com/leonatwork/Tappi/issues/18

## Baseline and available requirements

Work started with a clean checkout at
`27ba3ce11fb27a640ac99a4f926ec05f5afd6ad7`, identical to local `origin/master`.
Git metadata identifies `origin/HEAD -> origin/master`, and `build.yml` targets
`master`. There is no local `origin/main`; the supplied main-only instruction
cannot be followed literally. The checked-out default-branch commit was used.
No branch was created or checked out, and no open-PR changes were incorporated.

GitHub CLI access is denied by the environment policy. The complete issue thread,
comments, current remote default branch and open PRs could not be verified.
Requirements below derive from the full issue description supplied in the task
and the checked-out code. `CLAUDE.md` and `AGENTS.md` are absent from this
checkout; `CONTRIBUTING.md` was read and followed.

The baseline already includes #11 (PR #22), #13 (PR #20) and #17 (PR #25).
Their settings decoding, identity-abstracted `WindowMerge`, parameterized layout
and existing tests are reused. No known open-PR dependency is required; live PR
overlap remains unchecked.

## Implementation and coverage

- `SwitcherSession` keeps only state and selected index. The controller retains
  its existing window list, timers, panel, keyboard routing and focus actions.
  Begin, cycling, modifier release, explicit commit and cancellation are pure
  decisions; MRU promotion occurs only on the controller's commit path.
- `MRUOrdering.promote` is shared by the real store and value-only tests. The
  store still finds windows by reference identity before promoting them.
- `WindowSessionList.make` filters cached window facts with explicit settings,
  scope and frontmost PID. `WindowEntry` conforms to the small facts protocol;
  tests use values with no AX elements or live workspace access.
- `SwitcherSessionTests` covers index 1, consecutive toggles, stable MRU while
  cycling, promotion preserving other ranks, initial Shift, wrap in both
  directions, Esc, sticky release/commit, zero/one candidate, the existing
  displayed-prefix behavior, mouse/removal selection and invalid/current rank.
- `WindowSessionListTests` covers scope, absent frontmost PID, minimized, hidden,
  other Spaces, the minimized-Space exception and combined filters in MRU order.
- `TileLayoutTests` adds explicit column limits by preference, space and count,
  plus the 96-point minimum for undersized preferences. Existing tests already
  verify tile containment and the layout extracted by #17.
- `SettingsTests` adds fixed expected switcher defaults. Existing round-trip and
  decoding tests are retained; no settings-decoding behavior was changed.
- Build CI runs `swift scripts/check-localizations.swift`. Release CI runs
  `swift test -c release` before certificate import and `./build.sh`.

## Acceptance criteria and verification status

| Criterion | Delivery / remaining evidence |
| --- | --- |
| AC-1: all scoped rules tested and green under `swift test` | Coverage implemented, using only XCTest and the existing target. macOS execution and green results are outstanding. |
| AC-2: lost localization keys or mismatched placeholders fail build CI | Unconditional checker step added. Existing checker detects these cases and exits 1. Actual macos-15 CI and negative-fixture evidence are outstanding. |
| AC-3: a red tag test stops release before Build/publication | Unconditional test step precedes signing, Build, Package and Publish; default success gating stops subsequent steps on failure. YAML validation passed. No tag or release run was triggered. |
| AC-4: green tests retain build/sign/package behavior | Diff review confirms all existing release steps and triggers are intact. End-to-end release execution is unverified. |
| AC-5: unchanged behavior, approximately 1–2 ms panel latency | Source review preserves existing rules and displayed-prefix handling. The new state contains only scalars; step performs scalar arithmetic, without new arrays, closures or system calls. Runtime smoke tests and before/after latency measurements are outstanding. |
| AC-6: warning-free `swift build -c release` | Existing CI warning gate retained. Build and warning results are outstanding on macOS. |

For AC-3, “before Build” refers to the existing app-bundle Build step.
`swift test` necessarily compiles its target and tests; preventing all compilation
while also requiring `swift test -c release` would be contradictory.

### Test-first evidence and limits

The new session/filter tests and layout/default assertions were written before
production edits. A source search at that point confirmed that `SwitcherSession`,
`MRUOrdering`, `SessionWindow` and `WindowSessionList` did not exist in `Sources`.
The new session/filter tests therefore require the missing test seam before they
can compile. This issue protects existing correct behavior; the additional
layout/default assertions are expected to pass on the baseline already.

**No executed red/green proof is claimed.** The explicit server rules prohibit
building/running Swift or AppKit tests on Linux. This prevents the requested
pre-fix failure verification as well as post-fix execution here. The tests-only
stage was not committed, in accordance with the no-commit instruction.

Completed local checks: `git diff --check`, whitespace validation of all five
new files, source/diff review and static PyYAML parsing of both workflows.
The YAML check also verified the exact lint/test
commands, unconditional failure gating, test ordering before signing/Build,
`v*` release trigger and macos-15 build runner. No dependencies were added.

## Required macOS follow-up

1. Review the live issue comments and open PRs for additional requirements or
   overlap, and confirm the remote default-branch baseline.
2. If a pre-refactor red-stage artifact is required, apply only the new tests to
   the baseline in a scratch checkout and run `swift test`; record the missing
   test-seam compile failure separately from behavioral test failures.
3. On the complete change, run `swift test`, `swift test -c release`,
   `swift scripts/check-localizations.swift` and `swift build -c release`.
   Require a warning-free macos-15 Build CI run before acceptance.
4. In a disposable checkout, remove a translated key and separately change a
   placeholder type; verify the localization check exits nonzero in each case.
5. Smoke-test quick toggles between two windows, initial Shift, wrapping, Esc,
   sticky release/confirmation, one window and filtered lists. Compare
   `TAPPI_DEBUG=1` panel latency before/after with the same windows and settings,
   particularly with zero show delay. Record the actual measurements.

Changes are uncommitted. Nothing was pushed, released, deployed or merged.
