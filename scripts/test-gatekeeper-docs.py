"""Regression checks for first-launch instructions; run with Python 3."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
QUARANTINE_COMMAND = "xattr -dr com.apple.quarantine /Applications/Tappi.app"


class GatekeeperInstructionsTests(unittest.TestCase):
    def test_first_launch_in_each_installation_guide(self):
        guides = (
            ("README.md", "### Download the app", "### Build it yourself",
             ("double-click", "dismiss", "System Settings", "Privacy & Security",
              "scroll down", "Open Anyway", "password", "Touch ID", "Open")),
            ("README.de.md", "### Fertige App herunterladen", "### Selbst bauen",
             ("Doppelklick", "schließen", "Systemeinstellungen", "Datenschutz & Sicherheit",
              "nach unten", "Dennoch öffnen", "Passwort", "Touch ID", "Öffnen")),
            (".github/workflows/release.yml", "## Installation", "__SIGNING_NOTE__",
             ("double-click", "dismiss", "System Settings", "Privacy & Security",
              "scroll down", "Open Anyway", "password", "Touch ID", "Open")),
        )
        for filename, start, end, steps in guides:
            with self.subTest(file=filename):
                text = (ROOT / filename).read_text()
                installation = text.split(start, 1)[1].split(end, 1)[0]
                # Check the complete route in order, not just an isolated button name.
                cursor = 0
                for step in steps:
                    match = re.search(re.escape(step), installation[cursor:], re.IGNORECASE)
                    self.assertIsNotNone(match, f"Missing first-launch step: {step}")
                    cursor += match.end()
                self.assertIn(QUARANTINE_COMMAND, installation)
                self.assertRegex(installation, r"notari[sz]")

    def test_release_notes_heredoc_indentation(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        lines = workflow.splitlines()
        start = lines.index("          NOTES=$(cat <<'EOF'")
        end = lines.index("          EOF", start)
        self.assertGreater(end, start + 1)
        for line in lines[start + 1:end]:
            self.assertTrue(not line or line.startswith("          "), line)
        self.assertEqual(lines[end + 1], "          )")


if __name__ == "__main__":
    unittest.main()
