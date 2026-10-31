# Issue #33 — handover and verification limitations

Issue: https://github.com/leonatwork/Tappi/issues/33

The requested files and README sections are implemented. Full acceptance remains
partially unverified for the concrete reasons below; these limitations did not
prevent the repository-hygiene changes.

## Baseline and unavailable inputs

- HEAD is `a78fb9553d92c2d53b87343cfcccb68b3482f32b`, identical to the local
  `origin/master` reference. `origin/HEAD` points to `origin/master`, and
  `.github/workflows/build.yml` targets `master`. There is no local `origin/main`.
  The literal `origin/main` instruction therefore conflicts with the available
  default-branch metadata. Work uses the existing checkout; no branch was created
  or checked out, and no PR branch or cherry-pick was used. Remote freshness could
  not be confirmed.
- The environment permission policy denied GitHub CLI access. The full issue
  thread, comments, current remote default branch and existing PRs could not be
  read. Acceptance criteria below come from the supplied structured issue text,
  including the latest-release-only decision. Possible additional decisions or
  overlapping PRs remain unchecked. No open-PR dependency was established, and
  no open-PR work was incorporated.
- `CLAUDE.md` and `AGENTS.md` are absent from this checkout. `CONTRIBUTING.md`,
  the existing documentation regression script, build workflow and relevant
  source files were reviewed.

## Acceptance criteria and evidence

| Criterion | Result |
|---|---|
| AC-1 | `SECURITY.md` names GitHub Private Vulnerability Reporting, links the private report form and supports only the latest release. It contains no exploit details. Availability of the reporting feature is unverified. |
| AC-2 | `.github/CODEOWNERS` assigns `*` and `/.github/` to `@leonatwork`. |
| AC-3 | `.github/dependabot.yml` has version 2 and one weekly `github-actions` update for `/`. A real YAML parser validated both syntax and the resulting configuration. |
| AC-4 | The PR template asks why the change is needed, how it was tested and for before/after hotkey latency in ms with the CONTRIBUTING measurement command. |
| AC-5 | Both README sections describe no network requests by Tappi itself, local settings and diagnostics paths, and optional Screen Recording solely for previews. Browser-opened links and the existing settings backup are disclosed for accuracy. |
| AC-6 | `Sources/`, `Package.swift`, workflow files and `blank_issues_enabled` are unchanged. Repository settings were not modified. A warning-free release build remains unverified. |

The private reporting route depends on the owner enabling GitHub Private
Vulnerability Reporting if it is not already enabled. Changing that setting is
explicitly out of scope; the policy documents this prerequisite.

## Regression and quality checks

The tests were added before the hygiene files or README edits, following the
existing `scripts/test-gatekeeper-docs.py` Python unittest style. They exercise
the delivered repository documents rather than the macOS app, and introduce no
dependencies or build/CI gate.

- **Red:** `python3 scripts/test-repo-hygiene.py` ran six tests, all failing for
  the intended reasons: four missing files and two missing README sections.
- **Green:** the same command passes all six tests after the changes. One
  case-sensitive German assertion was corrected to accept `Fenstervorschauen`;
  this does not alter the original missing-section regression.
- `python3 scripts/test-gatekeeper-docs.py`: all three existing tests pass.
- Dependabot YAML: parsed with the environment's already installed PyYAML 6.0.1
  using `yaml.safe_load`; the parsed mapping equals the AC-3 configuration. No
  package was added or installed.
- `git diff --check`: passes.
- `git diff --exit-code -- Sources/ Package.swift .github/ISSUE_TEMPLATE/config.yml .github/workflows/`:
  passes, confirming the protected paths are unchanged.

README claims were compared with `Settings.swift:84–92, 116–137` (settings path
and conditional `.bak`), `Diagnostics.swift:7–30` and its call sites (local startup
log, reset on launch), `ThumbnailProvider.swift:54–56, 79–91, 136–156` (optional
preview capture), and `StatusItem.swift:260–263` (links delegated to the browser).
A targeted source search found no URLSession/URLRequest or Network/NWConnection
client; this is a source review, not a runtime network trace.

## Required follow-up

On an allowed macOS host, run the existing workflow checks: `swift scripts/check-localizations.swift`,
`swift build -c release` with the workflow's warning check, `swift test -c release`
and `./build.sh`. None were run here: the server lacks Swift/Xcode/AppKit, and the
task explicitly prohibits building or executing the app/Swift tests on Linux.
The warning-free build criterion cannot honestly be marked as verified here.

Before acceptance, review the unavailable GitHub comments and overlapping PRs,
confirm the remote baseline and check private-reporting availability. Changes are
uncommitted; no push, deployment, production-data change or merge was performed.
