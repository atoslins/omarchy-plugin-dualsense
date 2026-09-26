"""bin/dualsense-ctl without a controller: parsing, validation, the status
payload the panel reads, and the exact bytes of the reports it sends.

The report bytes are pinned to what 1.0.3 sends. The controller acts on every
bit of them, so a change here changes what it receives and should be
deliberate.
"""

import contextlib
import io
import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from unittest import mock

from support import ROOT, load, manifest

ctl = load("bin/dualsense-ctl", "dualsense_ctl")


def fresh_profile():
    return json.loads(json.dumps(ctl.DEFAULT_PROFILE))


class FakeController(ctl.Controller):
    """A Controller whose reports go to a pipe instead of a hidraw node."""

    def __init__(self, bus="usb"):
        super().__init__({"bus": bus, "node": "/dev/hidraw-test"})


class ParseColorTest(unittest.TestCase):
    def test_accepted_forms(self):
        for text, rgb in [
            ("#ff4000", (255, 64, 0)),
            ("FF4000", (255, 64, 0)),
            ("#f40", (255, 68, 0)),
            ("255, 64, 0", (255, 64, 0)),
            ("300,-5,0", (255, 0, 0)),
            ("red", (255, 32, 32)),
            ("off", (0, 0, 0)),
        ]:
            with self.subTest(text=text):
                self.assertEqual(ctl.parse_color(text), rgb)

    def test_rejects_garbage(self):
        for text in ("#ff40", "1,2", "blurple", "zzzzzz", ""):
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    ctl.parse_color(text)


# effect -> {strength: (mode, parameter bytes)}
TRIGGER_BYTES = {
    "off": {1: (0x05, ""), 5: (0x05, ""), 8: (0x05, "")},
    "feedback": {1: (0x21, "fc0300000000000000"), 5: (0x21, "fc0300499224000000"),
                 8: (0x21, "fc03c0ffff3f000000")},
    "weapon": {1: (0x25, "440000"), 5: (0x25, "440004"), 8: (0x25, "440007")},
    "bow": {1: (0x22, "420000"), 5: (0x22, "420024"), 8: (0x22, "42003f")},
    "galloping": {1: (0x23, "04011501"), 5: (0x23, "04011503"), 8: (0x23, "04011505")},
    "machine": {1: (0x27, "0201080803"), 5: (0x27, "02012c0803"), 8: (0x27, "02013f0803")},
    "vibration": {1: (0x26, "fc030000000000000a"), 5: (0x26, "fc030049922400000a"),
                  8: (0x26, "fc03c0ffff3f00000a")},
}


class TriggerTest(unittest.TestCase):
    def test_every_effect_is_pinned(self):
        self.assertEqual(sorted(TRIGGER_BYTES), sorted(ctl.TRIGGER_EFFECTS))

    def test_parameter_bytes(self):
        for effect, by_strength in TRIGGER_BYTES.items():
            for strength, (mode, params) in by_strength.items():
                with self.subTest(effect=effect, strength=strength):
                    got_mode, got_params = ctl.trigger_params(effect, strength)
                    self.assertEqual(got_mode, mode)
                    self.assertEqual(bytes(got_params).hex(), params)

    def test_strength_is_clamped(self):
        self.assertEqual(ctl.trigger_params("weapon", 0), ctl.trigger_params("weapon", 1))
        self.assertEqual(ctl.trigger_params("weapon", 99), ctl.trigger_params("weapon", 8))

    def test_pack_zones(self):
        self.assertEqual(bytes(ctl.pack_zones([0, 0] + [5] * 8)).hex(), "fc0300499224000000")
        self.assertEqual(bytes(ctl.pack_zones([8] * 10, 10)).hex(), "ff03ffffff3f00000a")

    def test_unknown_effect(self):
        with self.assertRaises(ValueError):
            ctl.trigger_params("laser")


DEFAULT_REPORT = ("0c570000000000000000050000000000000000000005000000000000000000000000"
                  "000000000100000000241546b2")
CUSTOM_REPORT = ("fc5700004c3c203001102242003f000000000000002544000400000000000000000000"
                 "000200030000020024000000")
ACCENT_REPORT = ("0c570000000000000000050000000000000000000005000000000000000000000000"
                 "000000000100000000245571ad")


class ProfileReportTest(unittest.TestCase):
    def report(self, profile, accent=None):
        return bytes(ctl.build_profile_report(FakeController(), profile, accent)).hex()

    def test_default_profile(self):
        self.assertEqual(self.report(fresh_profile()), DEFAULT_REPORT)

    def test_every_section(self):
        p = fresh_profile()
        p["lightbar"]["enabled"] = False
        p["audio"].update(micMuted=True, speaker="internal", volume=60, micVolume=50)
        p["triggers"]["left"]["effect"] = "weapon"
        p["triggers"]["right"].update(effect="bow", strength=8)
        p["motors"]["rumble"] = 2
        self.assertEqual(self.report(p, "#7aa2f7"), CUSTOM_REPORT)

    def test_follow_theme_uses_the_accent(self):
        p = fresh_profile()
        p["lightbar"]["followTheme"] = True
        self.assertEqual(self.report(p, "#7aa2f7"), ACCENT_REPORT)
        self.assertEqual(self.report(p, None), DEFAULT_REPORT)


# report id, the 47-byte common block (flags 0x00 0x04, RGB at 44-46), padding;
# Bluetooth adds a sequence byte, a 0x10 tag and the CRC.
USB_LIGHTBAR = "02" + "0004" + "00" * 42 + "ff4000" + "00" * 15
BT_LIGHTBAR = "3130" + "10" + "0004" + "00" * 42 + "ff4000" + "00" * 24 + "0d0a3c13"


class FramingTest(unittest.TestCase):
    def send_lightbar(self, bus, seq=3):
        c = FakeController(bus)
        r, w = os.pipe()
        self.addCleanup(os.close, r)
        self.addCleanup(os.close, w)
        c.fd, c.seq = w, seq
        common = c.new_common()
        c.fill_lightbar(common, (255, 64, 0), 100)
        c.send(common)
        return c, os.read(r, 256)

    def test_usb(self):
        _, data = self.send_lightbar("usb")
        self.assertEqual(len(data), 63)
        self.assertEqual(data.hex(), USB_LIGHTBAR)

    def test_bluetooth(self):
        _, data = self.send_lightbar("bluetooth")
        self.assertEqual(len(data), 78)
        # hid-playstation: CRC-32 of the 0xA2 output seed and the first 74 bytes.
        crc = zlib.crc32(b"\xa2" + data[:74]) & 0xFFFFFFFF
        self.assertEqual(struct.unpack("<I", data[74:])[0], crc)
        self.assertEqual(data.hex(), BT_LIGHTBAR)

    def test_bluetooth_sequence_wraps(self):
        c, data = self.send_lightbar("bluetooth", seq=15)
        self.assertEqual(data[1], 0xF0)
        self.assertEqual(c.seq, 0)

    def test_power_off_feature_report(self):
        c = FakeController("bluetooth")
        c.fd = -1
        sent = []
        with mock.patch.object(ctl.fcntl, "ioctl", lambda fd, req, buf, mutate: sent.append((req, bytes(buf)))):
            c.power_off()
        (request, buf), = sent
        self.assertEqual(request, 0xC02F4806)  # HIDIOCSFEATURE(47)
        self.assertEqual(buf[:2], b"\x08\x02")
        crc = zlib.crc32(b"\x53" + buf[:43]) & 0xFFFFFFFF
        self.assertEqual(struct.unpack("<I", buf[43:47])[0], crc)


class ProfileSetTest(unittest.TestCase):
    def test_values_are_normalised(self):
        for key, raw, value in [
            ("lightbar.color", '"red"', "#ff2020"),
            ("lightbar.color", "#00FF88", "#00ff88"),
            ("lightbar.brightness", "150", 100),
            ("lightbar.followTheme", "on", True),
            ("lightbar.enabled", "false", False),
            ("player.leds", "9", 7),
            ("player.brightness", '"low"', "low"),
            ("triggers.left.strength", "0", 1),
            ("triggers.right.effect", '"galloping"', "galloping"),
            ("audio.volume", '""', None),
            ("audio.micVolume", "40", 40),
            ("audio.speaker", "null", None),
            ("audio.micLed", '"pulse"', "pulse"),
            ("motors.rumble", "12", 7),
        ]:
            with self.subTest(key=key, raw=raw):
                p = fresh_profile()
                self.assertEqual(ctl.profile_set(p, key, raw), value)
                node = p
                for part in key.split("."):
                    node = node[part]
                self.assertEqual(node, value)

    def test_rejected(self):
        for key, raw in [
            ("lightbar.nope", "1"),
            ("nope.color", '"red"'),
            ("triggers.both.effect", '"weapon"'),
            ("triggers.left.effect", '"laser"'),
            ("player.brightness", '"max"'),
            ("audio.micLed", '"blink"'),
            ("audio.speaker", '"hdmi"'),
            ("lightbar.brightness", '"bright"'),
        ]:
            with self.subTest(key=key, raw=raw):
                with self.assertRaises(ValueError):
                    ctl.profile_set(fresh_profile(), key, raw)


class ProfileFileTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = os.path.join(tmp.name, "dualsense", "profile.json")

    def write(self, text):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path, "w") as f:
            f.write(text)

    def test_missing_file_is_the_default(self):
        self.assertEqual(ctl.load_profile(self.path), ctl.DEFAULT_PROFILE)

    def test_unreadable_file_is_the_default(self):
        for text in ("{nope", "[]"):
            with self.subTest(text=text):
                self.write(text)
                self.assertEqual(ctl.load_profile(self.path), ctl.DEFAULT_PROFILE)

    def test_partial_file_is_merged(self):
        self.write('{"lightbar": {"color": "#00ff88"}}')
        p = ctl.load_profile(self.path)
        self.assertEqual(p["lightbar"]["color"], "#00ff88")
        self.assertEqual(p["lightbar"]["brightness"], 70)
        self.assertEqual(p["player"], ctl.DEFAULT_PROFILE["player"])

    def test_round_trip(self):
        p = fresh_profile()
        p["player"]["leds"] = 3
        ctl.save_profile(self.path, p)
        self.assertEqual(ctl.load_profile(self.path), p)
        self.assertFalse(os.path.exists(self.path + ".tmp"))


class CleanErrorsTest(unittest.TestCase):
    """Failures reach the panel as the last line of stderr, so they have to be
    one readable line with a meaningful exit code, never a traceback."""

    def run_main(self, argv):
        err = io.StringIO()
        with contextlib.redirect_stderr(err), self.assertRaises(SystemExit) as exit:
            ctl.main(argv)
        return exit.exception.code, err.getvalue()

    def test_profile_set_null_number(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, err = self.run_main(["--profile", os.path.join(tmp, "p.json"),
                                       "profile", "set", "player.leds", "null", "--no-apply"])
        self.assertEqual(code, 2)
        self.assertIn("player.leds must be a number", err)

    def test_profile_set_rejects_non_numbers(self):
        for key, raw in [("player.leds", "null"), ("lightbar.brightness", "[50]"),
                         ("triggers.left.strength", "true"), ("motors.trigger", '{"a": 1}')]:
            with self.subTest(key=key, raw=raw):
                with self.assertRaises(ValueError):
                    ctl.profile_set(fresh_profile(), key, raw)

    def reconnect(self, outcomes):
        run = mock.Mock(side_effect=outcomes)
        with mock.patch.object(ctl, "which", return_value="/usr/bin/bluetoothctl"), \
                mock.patch.object(ctl, "find_controllers", return_value=[]), \
                mock.patch.object(ctl, "bluetooth_controllers",
                                  return_value=[{"mac": "aa:aa"}, {"mac": "bb:bb"}]), \
                mock.patch.object(ctl.subprocess, "run", run):
            try:
                ctl.main(["reconnect"])
            finally:
                self.calls = [c.args[0][-1] for c in run.call_args_list]

    def test_reconnect_timeout_moves_on(self):
        timeout = ctl.subprocess.TimeoutExpired(["bluetoothctl", "connect", "AA:AA"], 25)
        ok = ctl.subprocess.CompletedProcess([], 0, stdout="Connection successful\n", stderr="")
        self.reconnect([timeout, ok])
        self.assertEqual(self.calls, ["AA:AA", "BB:BB"])

    def test_reconnect_all_timeouts(self):
        timeout = ctl.subprocess.TimeoutExpired(["bluetoothctl", "connect"], 25)
        err = io.StringIO()
        with contextlib.redirect_stderr(err), self.assertRaises(SystemExit) as exit:
            self.reconnect([timeout, timeout])
        self.assertEqual(exit.exception.code, 6)
        self.assertIn("Press the PS button", err.getvalue())

    def test_bluetoothctl_that_hangs(self):
        info = {"id": "aa:aa", "mac": "aa:aa", "model": "DualSense", "bus": "bluetooth",
                "node": "/dev/hidraw-test", "access": {"hidraw": True}}
        timeout = ctl.subprocess.TimeoutExpired(["bluetoothctl", "disconnect", "AA:AA"], 10)
        with mock.patch.object(ctl, "which", return_value="/usr/bin/bluetoothctl"), \
                mock.patch.object(ctl, "find_controllers", return_value=[info]), \
                mock.patch.object(ctl.subprocess, "run", side_effect=timeout) as run:
            code, err = self.run_main(["disconnect"])
        self.assertIn("timeout", run.call_args.kwargs)
        self.assertEqual(code, 2)
        self.assertIn("timed out", err)


class RumbleTest(unittest.TestCase):
    def controller(self, hidraw, event):
        return {"id": "aa:bb", "mac": "aa:bb", "model": "DualSense", "bus": "usb",
                "node": "/nonexistent/hidraw-test", "event": "/nonexistent/event-test",
                "access": {"hidraw": hidraw, "event": event}}

    def test_force_feedback_needs_no_hidraw_access(self):
        # The gamepad's evdev node is open to the seat user without the udev
        # rule; the hidraw node is not. Rumble must not touch hidraw first.
        played = []
        with mock.patch.object(ctl, "find_controllers", return_value=[self.controller(False, True)]), \
                mock.patch.object(ctl.Controller, "rumble_evdev", lambda c, s, w, ms: played.append((s, w, ms))):
            ctl.main(["rumble", "--strong", "90", "--weak", "50", "--ms", "10"])
        self.assertEqual(played, [(90, 50, 10)])

    def test_no_access_at_all(self):
        with mock.patch.object(ctl, "find_controllers", return_value=[self.controller(False, False)]), \
                contextlib.redirect_stderr(io.StringIO()) as err, \
                self.assertRaises(SystemExit) as exit:
            ctl.main(["rumble"])
        self.assertEqual(exit.exception.code, 4)
        self.assertIn("No access", err.getvalue())


class StatusTest(unittest.TestCase):
    """The panel parses this payload; its keys are part of the plugin's contract."""

    def status(self):
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(ctl, "find_controllers", return_value=[]), \
                mock.patch.object(ctl, "bluetooth_controllers", return_value=[]), \
                mock.patch.object(ctl, "theme_accent", return_value="#7aa2f7"):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                ctl.main(["--profile", os.path.join(tmp, "profile.json"), "status", "--json"])
        return json.loads(out.getvalue())

    def test_payload_without_controllers(self):
        data = self.status()
        self.assertEqual(set(data), {"controllers", "staleBluetooth", "profile", "profileFile",
                                     "accent", "tools", "version"})
        self.assertEqual(data["controllers"], [])
        self.assertEqual(data["staleBluetooth"], [])
        self.assertEqual(data["profile"], ctl.DEFAULT_PROFILE)
        self.assertEqual(data["accent"], "#7aa2f7")

    def test_version_is_the_manifest_version(self):
        self.assertEqual(ctl.VERSION, manifest()["version"])
        self.assertEqual(self.status()["version"], manifest()["version"])

    def test_version_through_a_symlink(self):
        # The README suggests linking the helper into ~/.local/bin.
        with tempfile.TemporaryDirectory() as tmp:
            link = os.path.join(tmp, "dualsense-ctl")
            os.symlink(os.path.join(ROOT, "bin", "dualsense-ctl"), link)
            out = subprocess.run([sys.executable, "-B", link, "--version"], capture_output=True, text=True)
        self.assertEqual(out.stdout.strip(), "dualsense-ctl " + manifest()["version"])


if __name__ == "__main__":
    unittest.main()
