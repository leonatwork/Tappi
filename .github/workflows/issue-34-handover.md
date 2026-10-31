# Issue #34 — CI/release workflow hardening

## Baseline and available requirements

The initial clean checkout was `a78fb9553d92c2d53b87343cfcccb68b3482f32b`,
identical to local `origin/master` and `origin/HEAD -> origin/master`.
`build.yml` also targets `master`. There is no `origin/main` in this checkout;
the task's baseline requirement is interpreted as the actual default branch,
consistent with existing repository handovers. No branches were created or
checked out, and no changes from other PR branches were incorporated.

The supplied structured issue description is the available acceptance contract.
The environment denied GitHub CLI access, so the full issue thread, comments,
current open PRs, remote default-branch metadata and possible PR dependencies
could not be checked. No dependency on an open PR is used by this implementation.
`CLAUDE.md` and `AGENTS.md` are absent from the checkout; `CONTRIBUTING.md` was
read. Ancestor-directory rule searches were denied by the environment.
The requested knowledge-base query returned no matching note.

## Acceptance criteria

- **AC-1 — implemented:** all four action references in the two workflows use
  full 40-character SHAs and version comments: checkout v5.0.0,
  upload-artifact v4.6.2 and download-artifact v4.3.0. Regression tests enforce
  the pin/comment format. Upstream SHA-to-tag resolution could not be independently
  rechecked with the blocked GitHub access.
- **AC-2 — implemented:** `build.yml` grants only `contents: read` at workflow
  level.
- **AC-3 — implemented:** release `build` has only `contents: read`; tests,
  certificate import, build, conditional signature verification, packaging and
  upload stay there. Signature verification still precedes upload. `signed`
  is a job output. `publish` depends on `build`, has only `contents: write`,
  and runs only for tag pushes. Its two steps download the artifact and run the
  existing release-notes/`gh release create` script. `GH_REPO` supplies repository
  context without checkout. The new publish job has a five-minute timeout.
- **AC-4 — implemented:** the documentation test is a normal, required build
  step, without error suppression. The workflow regression suite also runs there.
- **AC-5 — locally verified:** ZIP and checksum transfer in the same named
  artifact. SHA-256 generation, `Tappi-<tag>.zip`, release title and complete
  notes (both signing variants) remain unchanged. Every manual dispatch,
  including dispatch on a tag, produces `Tappi-manual` containing
  `Tappi-manual.zip` and `checksum.txt`, and skips publishing.
- **AC-6 — partially verified:** no Swift files or `CODESIGN_IDENTITY` were
  changed. Green remote build/release runs are outstanding. They cannot be
  produced for these uncommitted changes while commits/pushes are forbidden
  and GitHub access is blocked. Linux has no Swift/Xcode/AppKit; no Swift build,
  app execution, XCTest run or signing command was attempted locally.

Manual dispatch on a tag previously met the old step-level tag condition and
could publish. The explicit requirement that manual runs publish nothing takes
precedence over preserving that edge case. Tag-push release behavior is preserved.
No production deployment, production-data access or notarization change occurred.

## Test-driven verification

The dependency-free regression suite lives under `.github/workflows/` to keep
all changes within the required diff scope. Its focused text checks enforce the
workflow security boundary; its behavioral test runs the actual publish shell
script in temporary directories with a local `gh` function that checks the
repository, token context and release arguments. It asserts the entire notes
file, including the checksum, for stable and ad-hoc signing. It never contacts
GitHub or publishes anything.

1. **Before the fix:** `python3 .github/workflows/test-workflows.py` ran eight
   tests and failed with ten assertion failures (including pinning subtests).
   Failures identified unpinned actions, missing read permissions, missing CI
   test steps and missing split jobs. The existing documentation suite already
   passed (three tests).
2. **After the fix:** all eight workflow tests and all three documentation tests
   passed.
3. Both workflow files parsed successfully using the already-installed PyYAML;
   `bash -n` passed for every parsed shell step. No dependency was added.
   `actionlint` is not installed; YAML validation is the permitted alternative.
4. `git diff --check` passed. The final changed/untracked paths are exclusively
   under `.github/workflows/`; this includes the tests and this handover.

Local commands:

```bash
python3 .github/workflows/test-workflows.py
python3 scripts/test-gatekeeper-docs.py
git diff --check
```

## Remaining acceptance evidence

Once the changes can be submitted by the maintainer:

1. Read the complete issue thread and current PRs; confirm no additional binding
   requirements or workflow conflicts, and resolve action SHAs against their
   upstream version tags.
2. Obtain a green Build PR run or dispatch on the submitted revision, including
   localization, warning-free release build, Swift tests, bundle assembly and
   both Python suites.
3. Dispatch Release on that revision: confirm `build` is green, `publish` is
   skipped, and `Tappi-manual` contains the ZIP and checksum. Dispatch on a tag
   must also skip publishing. No release-tag push is needed for this check.

Changes remain uncommitted. Nothing was pushed, deployed or merged.
