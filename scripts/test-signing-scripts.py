"""Signing regressions; run with Python 3, without Swift or a macOS keychain.

Execute copies of the complete scripts in a disposable directory. Build, signing
and installation commands are stubs: no app is built, installed or launched.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
STUB = r'''
import json
import os
from pathlib import Path
import secrets
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
entry = {"command": command, "args": args}
if command == "openssl" and args[0] == "pkcs12":
    source = args[args.index("-passout") + 1]
    entry["export_password"] = (os.environ.get(source[4:])
                                if source.startswith("env:") else source)
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(json.dumps(entry) + "\n")

if command == "security" and args[0] == "find-identity":
    print(os.environ.get("EXISTING_IDENTITY", ""))
elif command == "openssl" and args[0] == "rand":
    print(secrets.token_hex(int(args[-1])))
elif command == "codesign" and os.environ.get("SIGNING_FAIL") == "1":
    # The old fallback succeeds, reproducing a silently weakened signature.
    if "--options" in args:
        print("codesign: test identity not found", file=sys.stderr)
        sys.exit(42)
elif command == "git":
    sys.exit(1)  # No version stamping / absolute PlistBuddy invocation.
elif command == "swift" and "--show-bin-path" in args:
    print("unused-stub-bin")
'''


class SigningScriptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="tappi-signing-test-")
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.log = self.work / "commands.jsonl"
        self.environment = {
            **os.environ,
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "HOME": str(self.work),
            "TMPDIR": str(self.work),
            "COMMAND_LOG": str(self.log),
            "CODESIGN_IDENTITY": "",
            "VERSION": "",
            "EXISTING_IDENTITY": "",
            "SIGNING_FAIL": "0",
        }
        for name in ("security", "openssl", "codesign", "swift", "git"):
            self.stub(name)

    def stub(self, name):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\n{STUB}", encoding="utf-8")
        path.chmod(0o755)

    def run_script(self, name, *args, **environment):
        if name == "build.sh":
            (self.work / "dist/Tappi.app/Contents").mkdir(parents=True, exist_ok=True)
            # Stub filesystem/installation commands too, so --install is safe
            # even if a regression lets execution continue past failed signing.
            for command in ("cp", "rm", "mkdir", "pkill", "open"):
                self.stub(command)
        script = self.work / name
        shutil.copyfile(ROOT / name, script)
        return subprocess.run(
            ["bash", str(script), *args], cwd=self.work,
            env={**self.environment, **environment},
            capture_output=True, text=True, timeout=15,
        )

    def commands(self, name=None):
        entries = [json.loads(line) for line in self.log.read_text().splitlines()]
        return [entry for entry in entries if name is None or entry["command"] == name]

    def test_new_identity_uses_one_time_password_and_codesign_only_access(self):
        passwords = []
        for _ in range(2):
            result = self.run_script("setup-signing.sh")
            self.assertEqual(result.returncode, 0, result.stderr)
            exports = [call for call in self.commands("openssl")
                       if call["args"][0] == "pkcs12"]
            export = exports[-1]
            args = export["args"]
            self.assertTrue(args[args.index("-passout") + 1].startswith("env:"),
                            "PKCS#12 export must read its password from the environment")
            password = export["export_password"]
            self.assertTrue(password)
            self.assertNotEqual(password, "tappi")
            imports = [call["args"] for call in self.commands("security")
                       if call["args"][0] == "import"]
            imported = imports[-1]
            self.assertEqual(imported[imported.index("-P") + 1], password)
            self.assertNotIn("-A", imported)
            self.assertEqual(imported[imported.index("-T") + 1], "/usr/bin/codesign")
            self.assertEqual(imported.count("-T"), 1)
            self.assertNotIn(password, result.stdout + result.stderr)
            self.assertFalse(Path(args[args.index("-out") + 1]).parent.exists(),
                             "Temporary signing material must be cleaned up")
            passwords.append(password)
        self.assertNotEqual(*passwords, "Each setup must use a fresh password")
        random_calls = [call for call in self.commands("openssl")
                        if call["args"][0] == "rand"]
        self.assertEqual(len(random_calls), 2)

    def test_existing_identity_is_unchanged_with_access_notice(self):
        result = self.run_script("setup-signing.sh", "Custom Signing",
                                 EXISTING_IDENTITY='1) ABC "Custom Signing"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("nothing to do", result.stdout)
        self.assertRegex(result.stdout.lower(), r"older.*identit")
        self.assertIn("all apps", result.stdout.lower())
        self.assertEqual([call["args"][0] for call in self.commands("security")],
                         ["find-identity"])
        self.assertEqual(self.commands("openssl"), [])

    def test_signing_failure_aborts_without_fallback_or_installation(self):
        result = self.run_script("build.sh", "--install",
                                 CODESIGN_IDENTITY="Invalid Identity", SIGNING_FAIL="1")
        self.assertNotEqual(result.returncode, 0, "Failed signing must abort the build")
        self.assertIn("codesign: test identity not found", result.stderr)
        self.assertIn("signing failed", result.stderr.lower())
        self.assertIn("Invalid Identity", result.stderr)
        self.assertEqual(len(self.commands("codesign")), 1)
        self.assertEqual(self.commands("pkill"), [])
        self.assertEqual(self.commands("open"), [])
        self.assertNotIn("==> installing", result.stdout)
        self.assertNotIn("==> done", result.stdout)

    def test_explicit_release_identity_keeps_the_hardened_codesign_invocation(self):
        identity = "leonatwork Code Signing"
        result = self.run_script("build.sh", CODESIGN_IDENTITY=identity)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands("security"), [])
        self.assertEqual([call["args"] for call in self.commands("codesign")], [
            ["--force", "--sign", identity, "--options", "runtime",
             "--timestamp=none", "dist/Tappi.app"],
        ])
        self.assertIn("==> done: dist/Tappi.app", result.stdout)

    def test_local_and_ad_hoc_identity_selection_still_use_hardened_runtime(self):
        for existing, expected in (("Tappi Local Signing", "Tappi Local Signing"),
                                   ("", "-")):
            with self.subTest(identity=expected):
                result = self.run_script("build.sh", EXISTING_IDENTITY=existing)
                self.assertEqual(result.returncode, 0, result.stderr)
                args = self.commands("codesign")[-1]["args"]
                self.assertEqual(args[args.index("--sign") + 1], expected)
                self.assertEqual(args[args.index("--options") + 1], "runtime")


if __name__ == "__main__":
    unittest.main()
