# Issue #15 — macOS Gatekeeper instructions

Issue: https://github.com/leonatwork/Tappi/issues/15

## Scope and baseline

Updated the first-launch instructions in `README.md`, `README.de.md`, and the
release-notes heredoc in `.github/workflows/release.yml`. Each now describes a
blocked double-click launch followed by System Settings → Privacy & Security →
Open Anyway, authentication if prompted, and confirmation with Open. The German
instructions use Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen
and Öffnen. The quarantine-removal command remains available in all three places.
The existing README references to the first-launch step still apply.

The checkout's HEAD is `afd0d74234702728962fb2415656e56b375d5782`, identical to
the local `origin/master`. The task names `origin/main`, but that reference does
not exist here: `origin/HEAD` points to `origin/master`, and the build workflow
targets `master`. Work uses the checked-out default-branch baseline. No branch
was created or checked out, and no open-PR commits were incorporated.

`CONTRIBUTING.md`, the package minimum (macOS 14), and both workflows were read.
Neither `CLAUDE.md` nor `AGENTS.md` exists in this checkout. GitHub CLI access is
blocked by the environment's permission policy, so the full issue thread,
additional comments, repository metadata on GitHub, and existing PRs could not
be fetched. Acceptance criteria below come from the complete description supplied
in the task. No PR dependency is identified from that description; dependencies
in inaccessible comments or open PRs remain unverified.

## Acceptance criteria and evidence

| Criterion | Implementation / verification |
| --- | --- |
| AC-1: English instructions enable first launch on macOS 15. | Complete exception path documented; regression test verifies its ordered steps. Actual Gatekeeper behavior requires the manual Mac check below. |
| AC-2: German system menu/button labels are correct. | Uses the issue's specified German labels and the final Öffnen confirmation; documentation test passes. Live comparison with German macOS 15 remains pending. |
| AC-3: New tag notes contain the same path and `xattr` alternative. | Release-notes test passes; the parsed workflow's quoted heredoc was rendered locally with a dummy version, verifying both. No tag was built or published. |
| AC-4: Right-click is no longer the only documented path. | All three locations give the System Settings path and explicitly say right-click no longer bypasses Gatekeeper on macOS 15+. |
| AC-5: Valid YAML and unchanged heredoc indentation. | Parsed with existing PyYAML 6.0.1; baseline comparison proves everything outside the notes body, including heredoc delimiters and indentation, is unchanged. Parsed publish script also passes `bash -n`. |

No substantive acceptance criteria in the supplied description conflict. Runtime
acceptance of AC-1 and the live UI verification for AC-2 cannot be completed on
this Linux server. The baseline-name discrepancy and inaccessible GitHub checks
are documented above rather than treated as reasons to omit the requested fix.

## Test-driven verification

Added `scripts/test-gatekeeper-docs.py`, a standalone Python standard-library
documentation test. The reachable interface for this issue is the installation
text, not Swift app logic; an XCTest would require compiling the macOS app while
still only checking documentation. No dependency or CI step was added.

Before editing the three installation texts:

```text
python3 scripts/test-gatekeeper-docs.py
Ran 3 tests — FAILED (failures=3)
```

The English README and release notes failed on the missing dismissal instruction;
the German README failed on the missing “Meldung schließen” instruction. These
are genuine missing steps in the old right-click-only guidance.

After the fix:

- `python3 scripts/test-gatekeeper-docs.py`: all 3 tests pass.
- YAML parsing, for example:
  `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/release.yml"))'`:
  passes using the already-installed parser.
- Comparison against `git show HEAD:.github/workflows/release.yml`: only the
  heredoc body changed; delimiters and surrounding workflow are identical.
- `bash -n` on the parsed Publish release script: passes.
- Local execution of only the notes heredoc with `VERSION=v0.0.0-check`: produced
  the expected ZIP name, settings path, Open Anyway, and quarantine command.
- `git diff --check`: passes.

The repository's Swift release build, warning gate, app assembly, Swift tests,
and localization script were not run: the task explicitly prohibits app builds
and execution on this Linux server without Swift/Xcode/AppKit. No app code or
localized resource strings changed. No release workflow was dispatched.

## Required manual follow-up

1. On macOS 15 with English system language, download a fresh existing release ZIP,
   unzip it, and drag Tappi.app into /Applications. Follow README step 2 without
   using the `xattr` alternative; verify Tappi launches after the settings exception.
2. Repeat with German system language and a fresh quarantined copy; compare
   Datenschutz & Sicherheit, Dennoch öffnen, and Öffnen with the displayed labels.
3. If needed, check the same settings path on supported macOS 14. It is the primary
   path for both versions, as specified by the issue.

Changes are uncommitted. Nothing was pushed, released, deployed, or merged.
