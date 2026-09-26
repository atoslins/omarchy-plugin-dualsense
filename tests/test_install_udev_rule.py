"""udev/install-udev-rule against a scratch rules directory.

Pointed anywhere but /etc/udev/rules.d the installer runs unprivileged, which
lets these tests drive the same verification the root install goes through.
"""

import hashlib
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

from support import ROOT

INSTALLER = os.path.join(ROOT, "udev", "install-udev-rule")
RULE = os.path.join(ROOT, "udev", "71-dualsense-ctl.rules")
RULE_NAME = os.path.basename(RULE)


class InstallerTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = tmp.name
        self.dest = os.path.join(self.tmp, "rules.d")
        os.mkdir(self.dest)
        with open(RULE, "rb") as f:
            self.rule = f.read()

    def run_installer(self, *args):
        return subprocess.run([sys.executable, INSTALLER, *args, "--dest-dir", self.dest, "--no-reload"],
                              capture_output=True, text=True, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))

    def source(self, data, name="source.rules", mode=0o644):
        path = os.path.join(self.tmp, name)
        with open(path, "wb") as f:
            f.write(data)
        os.chmod(path, mode)
        return path

    def assert_refused(self, result, reason):
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn(reason, result.stderr)
        self.assertEqual(os.listdir(self.dest), [], "a refused install must leave nothing behind")

    def test_pinned_digest_is_the_shipped_rule(self):
        with open(INSTALLER) as f:
            pinned = re.search(r'^EXPECTED_SHA256 = "([0-9a-f]{64})"$', f.read(), re.M).group(1)
        self.assertEqual(pinned, hashlib.sha256(self.rule).hexdigest(),
                         "udev/71-dualsense-ctl.rules changed: review it, then update EXPECTED_SHA256")

    def test_install_check_remove(self):
        self.assertEqual(self.run_installer("check").returncode, 1)
        result = self.run_installer("install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.listdir(self.dest), [RULE_NAME])
        installed = os.path.join(self.dest, RULE_NAME)
        with open(installed, "rb") as f:
            self.assertEqual(f.read(), self.rule)
        self.assertEqual(stat.S_IMODE(os.stat(installed).st_mode), 0o644)
        self.assertEqual(self.run_installer("check").returncode, 0)
        self.assertEqual(self.run_installer("remove").returncode, 0)
        self.assertEqual(os.listdir(self.dest), [])

    def test_tampered_source(self):
        src = self.source(self.rule + b'KERNEL=="hidraw*", MODE="0666"\n')
        self.assert_refused(self.run_installer("install", "--source", src), "does not match the reviewed rule")

    def test_symlinked_source(self):
        link = os.path.join(self.tmp, "link.rules")
        os.symlink(RULE, link)
        self.assert_refused(self.run_installer("install", "--source", link), "symbolic link")

    def test_hard_linked_source(self):
        src = self.source(self.rule)
        os.link(src, os.path.join(self.tmp, "second.rules"))
        self.assert_refused(self.run_installer("install", "--source", src), "hard links")

    def test_world_writable_source(self):
        src = self.source(self.rule, mode=0o666)
        self.assert_refused(self.run_installer("install", "--source", src), "world-writable")

    def test_remove_keeps_a_file_that_is_not_ours(self):
        foreign = os.path.join(self.dest, RULE_NAME)
        shutil.copyfile(RULE, foreign)
        with open(foreign, "ab") as f:
            f.write(b"# edited\n")
        os.chmod(foreign, 0o644)
        self.assertEqual(self.run_installer("remove").returncode, 2)
        self.assertTrue(os.path.exists(foreign))
        self.assertEqual(self.run_installer("remove", "--force").returncode, 0)
        self.assertFalse(os.path.exists(foreign))


if __name__ == "__main__":
    unittest.main()
