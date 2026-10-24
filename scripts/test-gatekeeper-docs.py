"""Regression checks for the first-launch instructions; run with Python 3."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
QUARANTINE_COMMAND = "xattr -dr com.apple.quarantine /Applications/Tappi.app"


class GatekeeperDocumentationTests(unittest.TestCase):
    def check_instructions(self, text, steps):
        # Order matters: macOS offers the exception only after a blocked launch.
        position = 0
        for step in steps:
            match = re.search(step, text[position:], re.IGNORECASE)
            self.assertIsNotNone(match, f"Missing first-launch instruction: {step}")
            position += match.end()
        self.assertIn(QUARANTINE_COMMAND, text)

    def test_english_download_instructions(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        section = readme.split("### Download the app", 1)[1].split("### Build it yourself", 1)[0]
        self.check_instructions(section, (
            r"double-click", r"dismiss", r"System Settings", r"Privacy & Security",
            r"scroll down", r"Open Anyway", r"password or Touch ID", r"\bOpen\b",
        ))
        self.assertIn("not notarised", section)
        self.assertIn("first-launch step above", section)

    def test_german_download_instructions(self):
        readme = (ROOT / "README.de.md").read_text(encoding="utf-8")
        section = readme.split("### Fertige App herunterladen", 1)[1].split("### Selbst bauen", 1)[0]
        self.check_instructions(section, (
            r"Doppelklick", r"Meldung schließen", r"Systemeinstellungen",
            r"Datenschutz & Sicherheit", r"nach unten scrollen", r"Dennoch öffnen",
            r"Passwort oder Touch ID", r"\bÖffnen\b",
        ))
        self.assertIn("nicht notarisiert", section)
        self.assertIn("Schritt beim ersten Start oben", section)

    def test_release_notes_instructions_and_heredoc(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        # The raw indentation is significant: YAML strips ten spaces so Bash's
        # quoted heredoc terminator must then start in column zero.
        match = re.search(r"^          NOTES=\$\(cat <<'EOF'\n(.*?)^          EOF\n", workflow,
                          re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(match, "Release notes heredoc indentation changed")
        raw_notes = match.group(1)
        self.assertTrue(all(not line or line.startswith("          ")
                            for line in raw_notes.splitlines()))
        self.check_instructions(raw_notes, (
            r"double-click", r"dismiss", r"System Settings", r"Privacy & Security",
            r"scroll down", r"Open Anyway", r"password or Touch ID", r"\bOpen\b",
        ))
        self.assertIn("not notarised", raw_notes)


if __name__ == "__main__":
    unittest.main()
