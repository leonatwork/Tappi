"""Regression checks for issue #33; run with Python 3 (standard library only)."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RepositoryHygieneTests(unittest.TestCase):
    def read_document(self, path):
        file = ROOT / path
        self.assertTrue(file.is_file(), f"Missing repository document: {path}")
        return file.read_text(encoding="utf-8")

    def section(self, path, heading):
        text = self.read_document(path)
        match = re.search(rf"^## {re.escape(heading)}\n(.*?)(?=^## |\Z)", text,
                          re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(match, f"Missing {heading} section in {path}")
        return " ".join(match.group(1).split())

    def test_security_reporting_and_supported_release(self):
        text = " ".join(self.read_document("SECURITY.md").split())
        self.assertIn("GitHub Private Vulnerability Reporting", text)
        self.assertIn("https://github.com/leonatwork/Tappi/security/advisories/new", text)
        self.assertRegex(text, r"(?i)only the latest release")
        self.assertRegex(text, r"(?i)older releases are not supported")
        self.assertRegex(text, r"(?i)do not.*public.*(?:issue|exploit)")

    def test_codeowners_covers_repository_and_github(self):
        text = self.read_document(".github/CODEOWNERS")
        rules = [line.split() for line in text.splitlines()
                 if line.strip() and not line.lstrip().startswith("#")]
        self.assertIn(["*", "@leonatwork"], rules)
        self.assertIn(["/.github/", "@leonatwork"], rules)

    def test_dependabot_weekly_github_actions(self):
        # Check the required values without adding a YAML dependency to the repo.
        # A real YAML parser must also validate the file during review.
        text = self.read_document(".github/dependabot.yml")
        for pattern in (r"^version: 2$", r'^\s*- package-ecosystem: "github-actions"$',
                        r'^\s+directory: "/"$', r"^\s+schedule:$",
                        r'^\s+interval: "weekly"$'):
            self.assertRegex(text, re.compile(pattern, re.MULTILINE))
        self.assertEqual(text.count("package-ecosystem:"), 1)

    def test_pull_request_prompts(self):
        motivation = self.section(".github/PULL_REQUEST_TEMPLATE.md", "Motivation")
        self.assertRegex(motivation, r"(?i)why")
        testing = self.section(".github/PULL_REQUEST_TEMPLATE.md", "Testing")
        self.assertRegex(testing, r"(?i)how.*test")
        self.assertIn("swift build -c release", testing)
        measurement = self.section(".github/PULL_REQUEST_TEMPLATE.md", "Hotkey-path measurements")
        for term in ("before", "after", "ms", "TAPPI_DEBUG=1", "CONTRIBUTING.md"):
            self.assertIn(term, measurement)

    def check_local_files(self, section):
        for term in ("~/Library/Application Support/Tappi/", "settings.json",
                     "diagnostics.log", "settings.json.bak"):
            self.assertIn(term, section)

    def test_english_privacy(self):
        section = self.section("README.md", "Privacy")
        self.check_local_files(section)
        self.assertRegex(section, r"(?i)no network requests")
        self.assertRegex(section, r"(?i)screen recording.*optional.*only.*previews")
        self.assertRegex(section, r"(?i)links.*browser")

    def test_german_privacy(self):
        section = self.section("README.de.md", "Datenschutz")
        self.check_local_files(section)
        self.assertRegex(section, r"keine Netzwerkzugriffe")
        self.assertRegex(section, r"(?i)Bildschirmaufnahme.*optional.*nur.*Vorschau")
        self.assertRegex(section, r"Links.*Browser")


if __name__ == "__main__":
    unittest.main()
