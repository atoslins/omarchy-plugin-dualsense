"""CHANGELOG.md keeps the shape scripts/release and the Release workflow
depend on: an Unreleased section, one dated section per version, newest
first, and notes for the version in manifest.json."""

import os
import re
import subprocess
import unittest

from support import ROOT, manifest

HEADING = re.compile(r"^## \[(\d+\.\d+\.\d+)\] — (\d{4}-\d{2}-\d{2})$")


def key(version):
    return tuple(int(part) for part in version.split("."))


class ChangelogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, "CHANGELOG.md")) as f:
            cls.lines = f.read().splitlines()
        cls.versions = [m.group(1) for m in map(HEADING.match, cls.lines) if m]

    def test_unreleased_comes_first(self):
        headings = [line for line in self.lines if line.startswith("## ")]
        self.assertEqual(headings[0], "## [Unreleased]")

    def test_every_version_heading_is_dated(self):
        for line in self.lines:
            if line.startswith("## [") and line != "## [Unreleased]":
                self.assertRegex(line, HEADING)

    def test_newest_first(self):
        self.assertEqual(self.versions, sorted(self.versions, key=key, reverse=True))
        self.assertEqual(len(self.versions), len(set(self.versions)))

    def test_manifest_version_has_notes(self):
        version = manifest()["version"]
        self.assertIn(version, self.versions, "bump manifest.json with scripts/release")
        notes = subprocess.run([os.path.join(ROOT, "scripts", "release-notes"), version],
                               capture_output=True, text=True)
        self.assertEqual(notes.returncode, 0, notes.stderr)
        self.assertTrue(notes.stdout.strip())
        self.assertNotIn("## [", notes.stdout)


if __name__ == "__main__":
    unittest.main()
