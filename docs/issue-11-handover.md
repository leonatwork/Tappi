# Issue #11 — handover

Issue: https://github.com/leonatwork/Tappi/issues/11

## Baseline and available requirements

The working tree was clean before editing. HEAD is
`a6604c7a5bd21a753b084e9be80a3676a7a3ab33`, identical to the local
`origin/master`. Repository metadata has `origin/HEAD -> origin/master`, and
`.github/workflows/build.yml` targets `master`. There is no `origin/main` here:
the task's literal baseline name conflicts with the repository's actual default
branch. Work uses the checked-out default-branch commit. No branch was created
or checked out, and no open-PR code was inspected or incorporated.

GitHub CLI access was denied by the environment's permission policy. The complete
live issue thread, comments, open PRs, remote freshness and possible dependencies
could therefore not be checked. Requirements below come from the structured
issue description supplied in the task, including the resolved decisions to
default only an invalid field and back up an unreadable document.

`AGENTS.md` and `CLAUDE.md` are absent from this checkout. Access to ancestor
directories was denied. `CONTRIBUTING.md`, the existing XCTest style, package,
settings callers, language decoder and build workflow were reviewed. No new
dependencies, settings fields, value-range checks or CI infrastructure are added.

## Acceptance criteria and implementation

| Criterion | Implementation / evidence | Verification status |
| --- | --- | --- |
| AC-1: any missing non-optional key defaults only that field | Custom decoder reads defaults from one `Settings()` instance; test removes every key individually from a non-default fixture. | Source-reviewed; macOS test execution pending. |
| AC-2: `{}` equals `Settings()` | Empty-object test and per-field `decodeIfPresent` fallbacks. | Source-reviewed; macOS test execution pending. |
| AC-3: invalid values default only that field | Each field catches its own decoding error. Tests cover wrong scalar types, `holdModifier: "alt"`, `mouseHover: "yes"`, object values and nulls. Unknown language strings retain the existing `.system` behavior. | Source-reviewed; macOS test execution pending. |
| AC-4: invalid document at startup is logged and backed up before writing | `load()` logs existing unreadable files through `NSLog`; `save()` validates the existing document and atomically writes its original bytes to `settings.json.bak` before writing settings. | Source-reviewed; manual macOS verification pending. |
| AC-5: runtime read failure followed by `mutate()` preserves original in backup | The write-boundary validation does not depend on `knownModificationDate`, so it protects a failed reload even when that date has already been recorded. | Source-reviewed; manual macOS verification pending. |
| AC-6: unknown keys are ignored | Keyed decoding and a nested unknown-key regression case. | Source-reviewed; macOS test execution pending. |
| AC-7: encode/decode preserves all fields | Synthesized encoding is retained; `Settings` is `Equatable`; round-trip tests check defaults and a fixture with every field changed. | Source-reviewed; macOS test execution pending. |
| AC-8: tests pass in build.yml; documentation reflects behavior | Existing macos-15 workflow already runs `swift test -c release` and discovers the new test file. Both READMEs and `loadFromDisk()` comment updated. | Documentation complete; CI pass unverified. |

Loading never rewrites a file. Missing/invalid individual values in an otherwise
valid object do not require a backup. An unreadable document uses defaults at
startup and leaves current settings unchanged on reload. Before saving, a backup
replaces any previous `settings.json.bak`. If the original cannot be read or the
backup cannot be written, saving fails without overwriting `settings.json`.
`save()` reports success so `mutate()` records a write date only on success.

## Test-first work and checks

`Tests/TappiTests/SettingsTests.swift` was written before modifying product code.
It uses XCTest, `@testable import Tappi`, string JSON fixtures and in-memory
decoding only, as requested. In addition to the six requested categories it
covers nulls, the existing language fallback and invalid top-level documents.

The pre-fix source has synthesized decoding: missing non-optional keys throw
`keyNotFound`, null values throw `valueNotFound`, wrong types throw
`typeMismatch`, and an unknown modifier throws `dataCorrupted`. Thus the new
missing/invalid/empty-object cases exercise the reported regression. The initial
tests also require the requested `Equatable` conformance, absent before the fix.
This is a source-level analysis, **not an executed red-phase verification**.

The explicit Linux restriction prohibits building or running Swift/app tests on
this server. No `swift test`, release build, localization script or app execution
was attempted. An executed red/green proof and green macos-15 CI are therefore
not supplied. `git diff --check` passed; the final source and tests were manually
reviewed for field coverage, fallback isolation, encoding compatibility and
backup-before-write ordering.

Filesystem backup behavior has no automated test here: the issue explicitly
requests filesystem-free unit tests and manual Mac verification of backup
behavior. Decoding is tested at its reachable in-memory interface. The checks
below remain required for AC-4/AC-5, including failed-backup protection.

## Required macOS verification

1. Run `swift test --filter SettingsTests` against the original implementation
   with only `Equatable` added to permit the assertions to compile. Confirm the
   empty-object, missing-key, null and invalid-value regressions fail. Then run
   the same tests against the fix and confirm they pass.
2. Run `swift test -c release` and `swift build -c release`, including the existing
   `build.yml` warning check. Obtain the macos-15 CI result before acceptance.
3. Quit Tappi; set `tileSize` to 240 and `maxColumns` to 5 in settings.json and
   remove `mouseHover`. Start Tappi, verify 240/5 and the default mouse selection,
   then change a menu setting. Confirm the valid values survive and the missing
   field is written only when settings are saved.
4. With Tappi quit, record the exact contents of a syntax-invalid settings.json.
   Start Tappi; confirm the `NSLog` error and that loading has not rewritten the
   file. Change a menu setting and verify settings.json.bak matches the recorded
   bytes. Repeat with a non-object JSON document such as `[]`.
5. While Tappi runs, record the current preferences, replace settings.json with
   syntax-invalid JSON, and reopen the menu to trigger reload. Confirm the log
   and retained preferences. Change a menu setting; verify the backup has the
   hand-edited bytes, including when a prior backup already exists.
6. Make the backup destination unwritable, repeat an invalid-file save, and
   verify the error is logged and settings.json remains byte-for-byte unchanged.
   Restore normal permissions afterwards.

Use a disposable local settings profile for manual checks. No production
deployment, production data access, commit, push, PR creation or merge occurred.
The existing `NOTES-HANDOVER.md` for issue #12 is preserved.
