# Changelog

All notable changes to the DualSense plugin are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/); what counts as a breaking
change is spelled out in [CONTRIBUTING.md](CONTRIBUTING.md#versions).

## [Unreleased]

## [1.1.0] — 2026-09-26

After updating, restart the shell (`omarchy restart shell`): it keeps the
panel code it already loaded until it restarts.

### Fixed
- **The live input tester kept reading the first controller after switching
  in the picker** ([#1](https://github.com/atoslins/omarchy-plugin-dualsense/issues/1)).
  A running Quickshell `Process` keeps the command it was started with, so the
  tester stayed on the old `--device`; it now restarts on the controller you
  pick, and on the one the panel falls back to when the selected one
  disconnects. Reported, with the fix, by
  [@rhwaddell](https://github.com/rhwaddell).
- **Test rumble needed hidraw access it does not use.** Force feedback goes
  through the gamepad's input node, which the logged-in user can open without
  the udev rule, but the helper opened the hidraw node first and failed with
  "permission denied". `dualsense-ctl rumble`, the `rumble` IPC and the
  panel's **Test rumble** button now work without the rule.
- **`omarchy-shell atoslins.dualsense trigger <effect>` failed while the
  triggers were unlinked** ("Same effect on both triggers" off): it asked the
  helper for an unknown `triggers.both.effect` key. It now sets both triggers.
- **Helper errors are one readable line instead of a Python traceback.** A
  `null`, list or boolean for a numeric profile key now says
  `<key> must be a number`; `bluetoothctl` timing out during **Reconnect**
  moves on to the next controller and ends in the PS-button advice; and a hung
  `bluetoothctl disconnect` times out after 10 s instead of holding up every
  action queued behind it in the panel.
- **Settings written with `omarchy bar set` were misread.** Without `--json`
  the value is stored as text, so `notifications false` kept notifications on
  and `hideWhenDisconnected true` did nothing. Switches now take
  `true`/`false`, `on`/`off`, `yes`/`no` and `1`/`0`, as text or JSON;
  `pollSeconds` is kept within 1–3600 (0 used to poll non-stop) and
  `lowBattery` within 0–100.

### Changed
- **With no controller connected the widget checks once a minute instead of
  every 5 s.** Each check is a Python process costing about 55 ms of CPU. A
  controller that connects still shows up at once through the udev monitor,
  which is now restarted if it ever exits.
- New installs land in the right section of the bar.
- `dualsense-ctl --version` reads the version from `manifest.json`, the only
  place it is written now; 1.0.1 and 1.0.2 had shipped a helper that still
  said 1.0.0.
- The preview image is a 2:1 banner.

### Added
- The **Info** tab shows the plugin version.
- Tests for the helper, the udev installer and the manifest, run by CI on
  every push, and a release flow: every version is tagged `vX.Y.Z` and
  published as a GitHub release with its notes from this file.

## [1.0.3] — 2026-09-08

### Security
- **The udev rule is installed by a verifier pinned to the reviewed rule's
  SHA-256, instead of `sudo cp`.** Copying from the home directory as root
  left a window, between the password prompt and the copy, in which anything
  running as the user could swap the file — and a udev rule of an attacker's
  choosing hands out device permissions or runs actions as root.
  `udev/install-udev-rule` opens the source without following symlinks,
  checks that it is a regular, single-link, not world-writable file owned by
  root or by you, hashes the bytes it actually read, stages them root-owned
  with `O_EXCL`, verifies the staged copy, renames it into place atomically
  and verifies it again before reloading udev. `install-udev-rule check`
  reports the state without root; `remove` refuses to delete a file that is
  not the reviewed rule unless given `--force`.

## [1.0.2] — 2026-09-06

### Fixed
- **Reconnect no longer disconnects first.** A DualSense powers itself off the
  moment the host drops its link, so the disconnect that came before the
  reconnect turned a recoverable state into a controller that was simply off.
  It now only tries to connect.
- **The firmware report is read once and cached per controller** instead of on
  every poll: a cheap HID transfer over USB, but needless traffic on a
  Bluetooth link that already carries about 220 input reports a second.

### Added
- Troubleshooting for periodic Bluetooth drops (`hidp_send_message() … Resource
  temporarily unavailable`) and the `disable_ertm` mitigation.

## [1.0.1] — 2026-09-06

### Fixed
- **Lightbar stuck on the startup color.** The firmware keeps its own lightbar
  animation, ignoring the color in output reports, until it gets a setup
  report handing the lightbar over — the one the kernel's `hid-playstation`
  sends once at probe time. Every command that sets the lightbar now sends
  that handover first, in a report of its own.
- **Bluetooth link dropping while a slider was dragged.** Every slider step
  sent an output report, which filled the HID channel until BlueZ tore the
  session down, leaving the controller lit but gone from the plugin. Previews
  now send at most one report every 90 ms and skip the handover.

### Added
- The panel recognizes a Bluetooth link whose input session dropped and offers
  **Reconnect**.

## [1.0.0] — 2026-09-06

First release: battery and charging state in the bar, and a panel with the
lightbar, player LEDs, adaptive triggers, rumble, the built-in audio, a live
input tester and the controller's details, driven by `dualsense-ctl` (Python
standard library, hidraw and evdev). The profile is re-applied whenever a
controller connects. Controller art from dualshock-tools (MIT).
