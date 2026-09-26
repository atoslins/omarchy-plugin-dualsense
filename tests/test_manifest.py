"""manifest.json and the plugin folder against the checks that
omarchy-plugin-validate and the shell's PluginRegistry run before loading a
plugin, so a release cannot ship something `omarchy plugin update` rolls back.
"""

import os
import unittest

from support import ROOT, manifest

ENTRY_POINT_FOR_KIND = {
    "bar": "bar",
    "bar-widget": "barWidget",
    "menu": "menu",
    "overlay": "overlay",
    "panel": "panel",
    "service": "service",
}


class ManifestTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = manifest()

    def test_schema_version(self):
        self.assertIs(type(self.m.get("schemaVersion")), int)
        self.assertEqual(self.m["schemaVersion"], 1)

    def test_required_fields(self):
        for field in ("id", "name", "version", "kinds", "entryPoints"):
            with self.subTest(field=field):
                self.assertIn(field, self.m)

    def test_id(self):
        self.assertRegex(self.m["id"], r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
        self.assertNotIn("..", self.m["id"])
        self.assertFalse(self.m["id"].startswith("omarchy."))

    def test_version_is_semver(self):
        self.assertRegex(self.m["version"], r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")

    def test_entry_points(self):
        kinds, entry_points = self.m["kinds"], self.m["entryPoints"]
        self.assertIsInstance(kinds, list)
        self.assertTrue(kinds)
        self.assertIsInstance(entry_points, dict)
        for kind in kinds:
            if kind in ENTRY_POINT_FOR_KIND:
                self.assertIn(ENTRY_POINT_FOR_KIND[kind], entry_points, "kind %r needs an entry point" % kind)
        for path in entry_points.values():
            with self.subTest(path=path):
                self.assertFalse(os.path.isabs(path))
                self.assertNotIn("..", path)
                self.assertNotIn("\n", path)
                self.assertTrue(os.path.isfile(os.path.join(ROOT, path)))

    def test_default_section(self):
        section = self.m.get("barWidget", {}).get("defaultSection")
        if section is not None:
            self.assertIn(section, ("left", "center", "right"))

    def test_no_symlinks(self):
        for dirpath, dirnames, filenames in os.walk(ROOT):
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for name in dirnames + filenames:
                path = os.path.join(dirpath, name)
                self.assertFalse(os.path.islink(path), "omarchy-plugin-validate refuses symlinks: " + path)


if __name__ == "__main__":
    unittest.main()
