# DualSense — Omarchy bar widget

Your PlayStation DualSense (and DualSense Edge) at a glance in the Omarchy
Quattro bar, plus a floating panel that controls everything the controller
can do on Linux: lightbar, player LEDs, adaptive triggers, rumble, the
built-in microphone and speaker, a live input tester and the hardware details.
Works over USB-C and Bluetooth, alongside the kernel's `hid_playstation`
driver, with no extra packages.

![DualSense panel](preview.png)

- Gamepad glyph with the battery level beside it and a bolt while charging.
  Dimmed when no controller is connected; urgent color when the battery is
  low and not charging.
- Clicking opens a floating panel — the same popout style as the network and
  power widgets — with the battery bar, a DualSense drawing that shows the
  real lightbar color and player LEDs, and five tabs:
  - **Lights**: lightbar color from swatches, a hue slider or the theme accent
    (the bar follows every theme change), brightness, lightbar on/off; player
    LED pattern (off, 1–5) and LED brightness.
  - **Feel**: adaptive trigger effects for L2/R2 — off, resistance, weapon,
    bow, galloping, machine, vibration — with a strength slider, linked or per
    trigger; rumble and trigger motor strength; a rumble test through the same
    force-feedback path games use.
  - **Audio**: mute the built-in microphone, the mute LED (auto/off/on/pulse),
    mic gain, headphone/speaker routing and volume.
  - **Test**: live input drawn on the controller — every button lights, the
    sticks move, triggers fill, touches show on the touchpad, gyro and
    accelerometer read out below.
  - **Info**: model, connection, address, firmware build, hardware revision,
    kernel driver and device nodes, with permission problems called out.
- Everything you pick is saved to a profile and re-applied automatically when
  a controller connects (the kernel resets the lightbar on every connection).
- Desktop notifications (via the Omarchy shell) for: controller connected /
  disconnected, battery low, fully charged.
- Power off / disconnect buttons when the controller is on Bluetooth.
- Several controllers: a picker appears and each one is handled separately.
- Hot-plug aware (udev), polling every 5 s otherwise and every 2 s while the
  panel is open.

## Interactions

| Action | Result |
|---|---|
| Left / right click | Toggles the floating panel |
| Middle click | Refreshes now |
| Esc (panel open) | Closes the panel |

IPC:

```bash
omarchy-shell atoslins.dualsense open|close|toggle|refresh
omarchy-shell atoslins.dualsense lightbar '#ff4000'   # also: brightness 60, followTheme true
omarchy-shell atoslins.dualsense player 2            # 0 (off) to 5
omarchy-shell atoslins.dualsense trigger weapon      # off|feedback|weapon|bow|galloping|machine|vibration
omarchy-shell atoslins.dualsense mic off             # mute · `mic on` unmutes
omarchy-shell atoslins.dualsense rumble              # half-second test
omarchy-shell atoslins.dualsense apply               # re-apply the saved profile
omarchy-shell atoslins.dualsense poweroff            # Bluetooth only
omarchy-shell atoslins.dualsense tab test            # lights|feel|audio|test|info
```

## Install

```bash
omarchy plugin add https://github.com/atoslins/omarchy-plugin-dualsense
omarchy plugin enable atoslins.dualsense
```

Move it where you like: `omarchy bar move atoslins.dualsense --section right --index 3`.

## Remove

```bash
omarchy plugin remove atoslins.dualsense
```

The profile in `~/.config/dualsense/` stays; delete it if you want.

## Permissions

The plugin writes to the controller's hidraw node. Steam's `steam-devices`
package already grants that to the logged-in user, so if Steam is installed
you are done. Otherwise install the rule shipped in `udev/`:

```bash
sudo cp ~/.config/omarchy/plugins/atoslins.dualsense/udev/71-dualsense-ctl.rules /etc/udev/rules.d/
sudo udevadm control --reload && sudo udevadm trigger
```

then reconnect the controller. The same rule also opens the motion-sensor and
touchpad input nodes, which the **Test** tab needs for gyro, accelerometer and
touches (the gamepad itself works without it). The panel tells you when
access is missing.

## Bluetooth

Hold **Create** + **PS** until the lightbar blinks fast, then pick "Wireless
Controller" in the Bluetooth menu. Once paired it reconnects with the PS
button. The battery, lightbar, LEDs, triggers, audio and power-off all work
over Bluetooth; USB and Bluetooth report the battery in 10% steps (5, 15, …,
95, 100), which is what the controller sends.

## Games

The kernel driver exposes a standard gamepad, so SDL-based games and Steam
Input see the DualSense right away. Steam handles rumble, the lightbar and
adaptive triggers itself while a game runs and hands the controller back when
it exits; the plugin re-applies your profile on the next connection or with
**Reapply profile**.

## Settings

In the widget's entry in `~/.config/omarchy/shell.json`:

- `pollSeconds` (default `5`) — idle polling interval.
- `notifications` (default `true`) — desktop notifications.
- `lowBattery` (default `20`) — percentage that counts as low.
- `applyOnConnect` (default `true`) — re-apply the profile when a controller
  connects (and at shell start).
- `profileFile` (default `~/.config/dualsense/profile.json`) — where the
  profile lives.
- `showPercent` (default `true`) — battery percentage in the bar.
- `hideWhenDisconnected` (default `false`) — collapse the widget when no
  controller is connected instead of dimming it.

Example:

```json
{ "id": "atoslins.dualsense", "lowBattery": 15, "hideWhenDisconnected": true }
```

## Command line

`bin/dualsense-ctl` is a standalone tool (Python 3, standard library only)
that the panel drives; it is handy on its own:

```bash
ln -s ~/.config/omarchy/plugins/atoslins.dualsense/bin/dualsense-ctl ~/.local/bin/

dualsense-ctl status --pretty              # JSON snapshot of every controller
dualsense-ctl info                          # human readable details
dualsense-ctl lightbar '#ff4000' -b 80      # color + brightness; also: lightbar off|on
dualsense-ctl player 3 [--fade]             # 0–5 (6 outer pair, 7 inner three)
dualsense-ctl led-brightness low
dualsense-ctl trigger both weapon -s 6      # left|right|both · effects above
dualsense-ctl rumble --strong 80 --weak 40 --ms 500
dualsense-ctl mic off --led                 # mute + light the mute LED
dualsense-ctl speaker internal && dualsense-ctl volume 60
dualsense-ctl attenuation 2 0               # weaker rumble, full triggers
dualsense-ctl monitor                       # live input as JSON lines
dualsense-ctl profile set lightbar.color '#00ff88'
dualsense-ctl apply                         # re-apply the profile
dualsense-ctl poweroff                      # Bluetooth only
```

Add `--device MAC` to pick a controller, `--all` for every one.

## Requirements

- Omarchy 4 (Quattro) shell.
- Linux `hid_playstation` driver (kernel 5.12+, built into Omarchy).
- `python3` (already required by Omarchy), `udevadm` (systemd).
- Read/write access to the controller's hidraw node — see **Permissions**.
- Optional: `bluetoothctl` for the disconnect button.

## Credits

- Controller line art by [dualshock-tools](https://github.com/dualshock-tools/dualshock-tools.github.io)
  (© 2024 the_al, MIT), converted to QtQuick Shapes so it takes the theme
  colors — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- HID report layout documented by [dualsensectl](https://github.com/nowrep/dualsensectl)
  and the Linux `hid-playstation` driver.

## License

MIT — see [LICENSE](LICENSE).
