"""Dependency-free regression checks: python3 .github/workflows/test-workflows.py."""

from pathlib import Path
import os
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
TAG_BUILD = "github.event_name == 'push' && github.ref_type == 'tag'"
NOTES = """\
## Installation

1. Download and unzip `Tappi-v1.2.3.zip`
2. Drag `Tappi.app` into `/Applications`
3. On first launch, double-click `Tappi.app` once and dismiss the blocked-launch alert.
   Open **System Settings ▸ Privacy & Security**, scroll down to the Security section,
   and click **Open Anyway** for Tappi. Authenticate with your password or Touch ID if
   prompted, and confirm with **Open** to launch the app.

Step 3 allows Gatekeeper to open this app because this build is not notarised.
On macOS 15 and later, right-click ▸ Open no longer bypasses Gatekeeper. Alternatively:

```bash
xattr -dr com.apple.quarantine /Applications/Tappi.app
```

Tappi then asks for **Accessibility** (required) and **Screen Recording**
(optional, only for the window previews).

__SIGNING_NOTE__

Full changes: [CHANGELOG.md](https://github.com/leonatwork/Tappi/blob/master/CHANGELOG.md)"""


def job(workflow, name):
    # Only the fixed indentation used in these two workflows is needed here.
    match = re.search(rf"^  {name}:\n(.*?)(?=^  \w+:|\Z)", workflow,
                      re.MULTILINE | re.DOTALL)
    if match is None:
        raise AssertionError(f"Missing job: {name}")
    return match.group(1)


def step(job_text, name):
    match = re.search(rf"^      - name: {name}\n(.*?)(?=^      - |\Z)", job_text,
                      re.MULTILINE | re.DOTALL)
    if match is None:
        raise AssertionError(f"Missing step: {name}")
    return match.group(1)


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = (ROOT / ".github/workflows/build.yml").read_text()
        cls.release = (ROOT / ".github/workflows/release.yml").read_text()

    def test_actions_are_sha_pinned_with_versions(self):
        for workflow in (self.build, self.release):
            uses = re.findall(r"^\s*(?:- )?uses: (.+)$", workflow, re.MULTILINE)
            self.assertTrue(uses)
            for action in uses:
                with self.subTest(action=action):
                    self.assertRegex(action, r"^actions/[\w-]+@[0-9a-f]{40} # v\d+\.\d+\.\d+$")

    def test_build_workflow_is_read_only(self):
        self.assertRegex(self.build, r"(?m)^permissions:\n  contents: read\n")
        self.assertNotIn("write", self.build)

    def test_documentation_test_is_a_required_ci_step(self):
        docs = step(job(self.build, "build"), "Test Gatekeeper documentation")
        self.assertEqual(docs.strip(), "run: python3 scripts/test-gatekeeper-docs.py")

    def test_workflow_regressions_run_in_ci(self):
        checks = step(job(self.build, "build"), "Test workflows")
        self.assertEqual(checks.strip(), "run: python3 .github/workflows/test-workflows.py")

    def test_release_permissions_and_job_boundary(self):
        build = job(self.release, "build")
        publish = job(self.release, "publish")
        self.assertEqual(re.findall(r"^  (\w+):$", self.release, re.MULTILINE)[-2:],
                         ["build", "publish"])
        self.assertIn("    permissions:\n      contents: read\n", build)
        self.assertNotIn("write", build)
        self.assertIn("    permissions:\n      contents: write\n", publish)
        self.assertIn("    needs: build\n", publish)
        self.assertIn(f"    if: {TAG_BUILD}\n", publish)
        self.assertEqual(len(re.findall(r"^      - ", publish, re.MULTILINE)), 2)
        self.assertNotIn("actions/checkout", publish)
        self.assertIn("GH_REPO: ${{ github.repository }}", publish)
        self.assertIn("GH_TOKEN: ${{ github.token }}", publish)

    def test_signature_precedes_artifact_upload(self):
        build = job(self.release, "build")
        names = re.findall(r"^      - name: (.+)$", build, re.MULTILINE)
        self.assertEqual(names, ["Test", "Import signing certificate", "Build",
                                 "Verify signature", "Package", "Upload build"])
        verify = step(build, "Verify signature")
        self.assertIn("if: steps.signing.outputs.signed == 'true'", verify)
        self.assertIn('codesign --verify --strict "dist/Tappi.app"', verify)
        self.assertIn('grep "certificate leaf"', verify)
        signing = step(build, "Import signing certificate")
        self.assertIn('echo "CODESIGN_IDENTITY=leonatwork Code Signing"', signing)
        self.assertIn("    outputs:\n      signed: ${{ steps.signing.outputs.signed }}", build)
        self.assertIn("SIGNED: ${{ needs.build.outputs.signed }}", job(self.release, "publish"))

    def test_artifact_transfer_and_manual_build(self):
        build = job(self.release, "build")
        package = step(build, "Package")
        self.assertIn(f"VERSION: ${{{{ {TAG_BUILD} && github.ref_name || 'manual' }}}}", package)
        self.assertIn('ditto -c -k --keepParent dist/Tappi.app "Tappi-${VERSION}.zip"', package)
        self.assertIn('shasum -a 256 "Tappi-${VERSION}.zip" | tee checksum.txt', package)
        upload = step(build, "Upload build")
        self.assertNotIn("if:", upload)
        self.assertIn("uses: actions/upload-artifact@", upload)
        self.assertIn(f"name: Tappi-${{{{ {TAG_BUILD} && github.ref_name || 'manual' }}}}", upload)
        self.assertIn("            Tappi-*.zip\n            checksum.txt", upload)
        self.assertIn("if-no-files-found: error", upload)
        download = step(job(self.release, "publish"), "Download build")
        self.assertIn("uses: actions/download-artifact@", download)
        self.assertIn("name: Tappi-${{ github.ref_name }}", download)
        build_step = step(build, "Build")
        self.assertIn(f"VERSION: ${{{{ {TAG_BUILD} && github.ref_name || '' }}}}", build_step)

    def test_release_notes_and_assets_without_a_checkout(self):
        publish = job(self.release, "publish")
        script = textwrap.dedent(step(publish, "Publish release").split("        run: |\n", 1)[1])
        # Execute the real notes/CLI script, replacing only the external gh command.
        # This needs neither macOS nor GitHub access and never publishes a release.
        mock = """\
gh() {
  test "$GH_REPO" = "leonatwork/Tappi" || return 1
  test "$GH_TOKEN" = "test-token" || return 1
  test "$#" = 8 || return 1
  test "$1 $2 $3 $4" = "release create v1.2.3 Tappi-v1.2.3.zip" || return 1
  test "$5 $6 $7 $8" = "--title Tappi v1.2.3 --notes-file notes.md" || return 1
  test -f "$4" && test -f "$8"
}
"""
        signing_notes = {
            "true": "> **Note:** this build is signed with a stable certificate. Permissions granted once\n> survive later updates that are signed the same way.",
            "": "> **Note:** this build is ad-hoc signed. macOS ties granted permissions to the\n> signature, so they have to be granted again after an update.",
        }
        checksum = "a" * 64 + "  Tappi-v1.2.3.zip"
        for signed, signing_note in signing_notes.items():
            with self.subTest(signed=signed), tempfile.TemporaryDirectory() as directory:
                path = Path(directory)
                (path / "checksum.txt").write_text(checksum + "\n")
                (path / "Tappi-v1.2.3.zip").touch()
                result = subprocess.run(
                    ["bash", "-e", "-o", "pipefail", "-c", mock + script], cwd=path,
                    env={**os.environ, "GH_REPO": "leonatwork/Tappi", "GH_TOKEN": "test-token",
                         "VERSION": "v1.2.3", "SIGNED": signed}, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = NOTES.replace("__SIGNING_NOTE__", signing_note)
                expected += f"\n\n**SHA-256**\n```\n{checksum}\n```\n"
                self.assertEqual((path / "notes.md").read_text(), expected)


if __name__ == "__main__":
    unittest.main()
