# Issue #36 — handover

Issue: https://github.com/leonatwork/Tappi/issues/36

## Baseline and available requirements

The initially clean checkout is `a78fb9553d92c2d53b87343cfcccb68b3482f32b`,
identical to local `origin/master`. `origin/HEAD`, branch tracking and the build
workflow identify `master` as the default branch. No `origin/main` exists locally,
so the literal baseline instruction conflicts with the supplied repository.
Changes use only this supplied default-branch commit on the already checked-out
workspace branch. No other branch or PR code was incorporated.

GitHub CLI access is denied by the harness permission policy. The live issue
thread/comments, open PRs and remote freshness could not be checked. The supplied
structured issue's AC-1 through AC-6 and resolved decisions are the binding
available requirements; they supersede the original description where expanded.
No implementation dependency is apparent in the current code, but live PR
overlap/dependencies remain unverified. `AGENTS.md` and `CLAUDE.md` are absent
from this checkout; access to parent-directory rules is denied. Reviewed
`CONTRIBUTING.md`, README, both signing scripts, build/release workflows and the
existing Python regression-test convention under `scripts/`. The knowledge-base
query confirmed the local-signing workflow without providing additional rules.

## Acceptance criteria and evidence

| Criterion | Implementation and verification |
| --- | --- |
| AC-1: random one-time password, environment-based export, codesign-only key access | `openssl rand -hex 32` generates the transport password per setup; export uses `-passout env:PKCS12_PASSWORD`, import uses the matching password and only `-T /usr/bin/codesign`, without `-A`. The variable is unset after import. Regression checks two distinct passwords, environment transport, matching import password, restricted import arguments, no password output and temporary-directory cleanup. Actual keychain ACL behavior requires macOS. |
| AC-2: signing failure aborts with visible stderr, no weaker retry | The original Hardened Runtime invocation is attempted once. Failure prints an identity-specific message to stderr and exits 1 before installation. The negative regression simulates failure for an invalid explicit identity, with a stub that would succeed on the former weak fallback; it checks nonzero exit, visible codesign stderr, one attempt and no installation/launch. |
| AC-3: Bash syntax clean, no new ShellCheck findings | `bash -n setup-signing.sh build.sh` passed before and after the change. `shellcheck` is not installed, so the optional before/after comparison could not be performed. |
| AC-4: unchanged release workflow and explicit-identity signing invocation | `git diff --exit-code -- .github/workflows/release.yml` passed. The explicit release identity regression verifies the exact original arguments: `--force --sign IDENTITY --options runtime --timestamp=none dist/Tappi.app`, with no local identity lookup. Local identity and ad-hoc selection also remain covered. Real release execution remains unverified. |
| AC-5: existing identity unchanged, `nothing to do`, exit 0, additional notice | The early-exit path now mentions that older identities may permit access by all apps and are left unchanged. Regression verifies exit 0, both messages, only `find-identity` and no OpenSSL invocation. |
| AC-6: both documents explain first-build keychain dialog and signing-error abort | README and CONTRIBUTING include the possible one-time dialog, denied access/invalid identity examples, visible signing errors, abort before installation and no retry without Hardened Runtime. Source-reviewed. |

Certificate name/default identity, certificate lifetime, PKCS#12 compatibility
algorithms, GitHub secrets and release workflow retain their original behavior.
Existing identities are neither migrated nor regenerated.

## Test-first record

Added `scripts/test-signing-scripts.py` before changing the production scripts,
following the existing dependency-free Python `unittest` convention. The tests
execute complete copies of the shell scripts in disposable directories. OpenSSL,
security, codesign, Swift and build/installation commands are simulated; no
Swift build, real certificate generation, keychain access or app execution occurs.

The first harness run exposed a missing disposable `Contents` directory for the
script's PkgInfo redirection. After correcting only that fixture, the pre-fix run
of `python3 scripts/test-signing-scripts.py -v` produced **three expected failing
tests and two passing compatibility tests**:

- Missing older-identity access notice.
- Fixed password export instead of an environment-sourced one-time password.
- Invalid-identity signing returned exit 0 because the weak fallback succeeded.

After the production fix, the same command passed **all five tests**. These are
executed shell-behavior regressions with simulated tools, not native macOS
signing evidence. No tests under `Tests/`, Swift builds, localization tools or
app builds were run, in accordance with the Linux execution restriction.
`git diff --check` also passed.

## Remaining verification before acceptance

1. Read the live issue comments and open PRs; reconcile any unavailable decisions
   or overlap, and confirm the supplied default-branch baseline is current.
2. If ShellCheck is available, compare both baseline scripts with this patch:
   `shellcheck setup-signing.sh build.sh`. No dependencies were installed here.
3. On a development Mac, run `./setup-signing.sh`, then `./build.sh` using the
   local identity. If the identity already exists, confirm `nothing to do`, the
   additional notice and unchanged identity. That path intentionally cannot prove
   new-import ACLs; verify a fresh setup only on a separate development account
   without an existing identity. Inspect the imported key's access control: no
   all-app access and `codesign` authorized. Check the possible first-build
   keychain dialog and successful Hardened Runtime signature.
4. On that Mac, run `CODESIGN_IDENTITY="Invalid Identity" ./build.sh` and confirm
   visible codesign diagnostics, the abort message and nonzero exit. Do not use
   `--install` for this negative check.
5. Run the existing prescribed macOS quality checks: warning-free
   `swift build -c release`, `swift test -c release` and
   `swift scripts/check-localizations.swift`; verify bundle assembly and signing
   with an explicitly set valid `CODESIGN_IDENTITY` in a development environment.

Changes are local and uncommitted. No branch creation, commit, push, PR creation,
merge, deployment or production-data access occurred.
