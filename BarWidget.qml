import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// DualSense controller glyph with the battery level in the bar; clicking it
// opens a floating panel — the same popout the network and power widgets use —
// with the battery, the lightbar and player LEDs, adaptive trigger effects,
// rumble, the built-in audio, a live input tester and the controller details.
// Everything talks to the controller through bin/dualsense-ctl (hidraw/evdev,
// no dependencies) and the choices persist in a profile that is re-applied
// whenever a controller connects.
Panel {
  id: root
  moduleName: "atoslins.dualsense"
  ipcTarget: "atoslins.dualsense"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the lightbar/player/rumble methods below.
  manageIpc: false

  // ---------- settings (this widget's entry in shell.json) ----------
  readonly property int pollSeconds: setting("pollSeconds", 5)
  readonly property bool notificationsEnabled: setting("notifications", true) !== false
  readonly property int lowBattery: setting("lowBattery", 20)
  readonly property bool applyOnConnect: setting("applyOnConnect", true) !== false
  readonly property string profileSetting: String(setting("profileFile", "~/.config/dualsense/profile.json"))
  readonly property string profileFile: profileSetting.indexOf("~") === 0 ? Quickshell.env("HOME") + profileSetting.substring(1) : profileSetting
  readonly property bool showPercent: setting("showPercent", true) !== false
  readonly property bool hideWhenDisconnected: setting("hideWhenDisconnected", false) === true

  // ---------- live state ----------
  property var controllers: []
  property string selectedMac: ""
  property var profile: null
  property string themeAccent: ""
  property bool helperOk: true
  property string lastError: ""
  property bool busy: false
  property string tab: "lights"
  property bool testerOn: false
  property var live: null
  property bool linkTriggers: true

  // Poll-to-poll diff state for notifications and apply-on-connect.
  property bool _primed: false
  property var _prev: ({})
  property var _lowNotified: ({})
  property var _queue: []
  property var staleLinks: []
  property string _pendingHex: ""
  property real _pendingBrightness: -1

  readonly property bool vertical: bar ? bar.vertical === true : false
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string face: bar ? bar.fontFamily : Style.font.family
  readonly property string glyph: "󰊗"
  readonly property string helper: Qt.resolvedUrl("bin/dualsense-ctl").toString().replace(/^file:\/\//, "")
  readonly property string accentHex: String(Color.accent).substring(0, 7)

  readonly property var device: {
    for (var i = 0; i < controllers.length; i++)
      if (controllers[i].mac === selectedMac) return controllers[i]
    return controllers.length > 0 ? controllers[0] : null
  }
  readonly property bool connected: device !== null
  readonly property bool canControl: connected && device.access && device.access.hidraw === true
  readonly property bool canRumble: connected && device.access
    && (device.access.event === true || device.access.hidraw === true)
  readonly property bool bluetooth: connected && device.bus === "bluetooth"
  readonly property int capacity: connected && device.battery && device.battery.capacity !== null
    ? device.battery.capacity : -1
  readonly property string batteryStatus: connected && device.battery ? String(device.battery.status) : "unknown"
  readonly property bool charging: batteryStatus === "charging"
  readonly property bool full: batteryStatus === "full"
  readonly property bool low: capacity >= 0 && capacity <= lowBattery && !charging && !full

  readonly property var lightbar: profile && profile.lightbar ? profile.lightbar : ({ enabled: true, color: "#1e64ff", brightness: 70, followTheme: false })
  readonly property var player: profile && profile.player ? profile.player : ({ leds: 1, fade: false, brightness: "high" })
  readonly property var triggers: profile && profile.triggers ? profile.triggers : ({ left: { effect: "off", strength: 5 }, right: { effect: "off", strength: 5 } })
  readonly property var audio: profile && profile.audio ? profile.audio : ({ micMuted: false, micLed: "auto", speaker: null, volume: null, micVolume: null })
  readonly property var motors: profile && profile.motors ? profile.motors : ({ rumble: 0, trigger: 0 })

  readonly property int ledPattern: [0, 4, 10, 21, 27, 31, 17, 14][Math.max(0, Math.min(7, Number(player.leds)))]
  readonly property string lightbarHex: lightbar.followTheme ? accentHex : String(lightbar.color || "#1e64ff")
  readonly property color lightbarColor: {
    var c = Qt.color(lightbarHex)
    var b = Math.max(0, Math.min(100, Number(lightbar.brightness))) / 100
    return Qt.rgba(c.r * b, c.g * b, c.b * b, 1)
  }
  readonly property color heroColor: connected && lightbar.enabled !== false ? Qt.lighter(lightbarColor, 1.15) : dim

  readonly property var swatches: ["#1e64ff", "#00e0ff", "#20ff50", "#ffd000", "#ff7a00", "#ff2020", "#ff40b0", "#a020ff", "#ffffff"]
  readonly property var triggerOptions: [
    { value: "off", label: "Off" },
    { value: "feedback", label: "Resistance", tooltip: "Constant resistance past a point" },
    { value: "weapon", label: "Weapon", tooltip: "Resist, then snap like a trigger" },
    { value: "bow", label: "Bow", tooltip: "Growing tension, releases at the end" },
    { value: "galloping", label: "Galloping", tooltip: "Rhythmic double pulse" },
    { value: "machine", label: "Machine", tooltip: "Fast mechanical rattle" },
    { value: "vibration", label: "Vibration", tooltip: "Buzz past a point" }
  ]
  readonly property var micLedOptions: [
    { value: "auto", label: "Auto", tooltip: "Lit while muted" }, { value: "off", label: "Off" },
    { value: "on", label: "On" }, { value: "pulse", label: "Pulse" }
  ]
  readonly property var speakerOptions: [
    { value: "", label: "Default" }, { value: "headphone", label: "Headphones" },
    { value: "internal", label: "Speaker" }, { value: "both", label: "Both" }
  ]
  readonly property var tabOptions: [
    { value: "lights", label: "Lights" }, { value: "feel", label: "Feel" },
    { value: "audio", label: "Audio" }, { value: "test", label: "Test" }, { value: "info", label: "Info" }
  ]

  readonly property string heroTitle: connected ? String(device.model) : "DualSense"
  readonly property string heroMeta: {
    if (!helperOk) return "Helper failed · " + (lastError || "see logs")
    if (!connected) return "No controller · USB or Bluetooth"
    var parts = [bluetooth ? "Bluetooth" : "USB"]
    if (capacity >= 0) parts.push(capacity + "%")
    parts.push(full ? "Full" : charging ? "Charging" : batteryStatus === "discharging" ? "On battery" : batteryStatus)
    if (!canControl) parts.push("no hidraw access")
    return parts.join(" · ")
  }
  readonly property string batteryLabel: {
    if (!connected) return ""
    if (capacity < 0) return "Battery level unknown"
    if (full) return "Fully charged"
    if (charging) return "Charging · " + capacity + "%"
    if (low) return "Battery low · " + capacity + "%"
    return capacity + "% · reported in 10% steps"
  }
  readonly property color batteryColor: low ? urgent : charging || full ? Color.accent : fg

  // ---------- helpers ----------
  function refresh() {
    if (!poll.running) poll.running = true
  }

  function open() {
    root.controller.show()
    root.refresh()
  }

  function notify(headline, body, urgency, glyph) {
    if (!notificationsEnabled || !bar) return
    var clean = function(s) { return String(s).replace(/['"\\]/g, "") }
    bar.run("omarchy-notification-send --app-name DualSense -g '" + clean(glyph || root.glyph)
      + "' -u " + (urgency || "low") + " '" + clean(headline) + "' '" + clean(body) + "'")
  }

  // Queue a dualsense-ctl invocation; jobs run one at a time in order.
  function ctl(args, after) {
    _queue.push({ args: args, after: after || null })
    pump()
  }

  function pump() {
    if (act.running || _queue.length === 0) return
    var job = _queue.shift()
    act.job = job
    act.err = ""
    act.command = ["python3", helper, "--profile", profileFile].concat(job.args)
    root.busy = true
    act.running = true
  }

  function deviceArgs() {
    return connected && device.mac ? ["--device", device.mac] : []
  }

  // Update the local profile immediately (so sliders and chips never jump),
  // then persist and apply through the helper. The next poll reconciles.
  function setProfile(key, value) {
    var copy = JSON.parse(JSON.stringify(profile || {}))
    var parts = key.split(".")
    var node = copy
    for (var i = 0; i < parts.length - 1; i++) {
      if (typeof node[parts[i]] !== "object" || node[parts[i]] === null) node[parts[i]] = {}
      node = node[parts[i]]
    }
    node[parts[parts.length - 1]] = value
    root.profile = copy
    ctl(["--all", "profile", "set", key, JSON.stringify(value), "--accent", accentHex, "--no-apply"], function(code) {
      if (code === 0 && root.canControl) ctl(["--all", "apply", "--accent", root.accentHex])
    })
  }

  function setLightbarColor(hex) {
    var copy = JSON.parse(JSON.stringify(profile || {}))
    if (!copy.lightbar) copy.lightbar = {}
    copy.lightbar.color = hex
    copy.lightbar.followTheme = false
    copy.lightbar.enabled = true
    root.profile = copy
    ctl(["--all", "profile", "set", "lightbar.followTheme", "false", "--no-apply"])
    ctl(["--all", "profile", "set", "lightbar.enabled", "true", "--no-apply"])
    ctl(["--all", "profile", "set", "lightbar.color", JSON.stringify(hex), "--accent", accentHex])
  }

  // side is "left", "right" or "both" (the IPC), whatever the link toggle says.
  function setTrigger(side, effect) {
    if (linkTriggers || side === "both") {
      setProfile("triggers.left.effect", effect)
      setProfile("triggers.right.effect", effect)
    } else {
      setProfile("triggers." + side + ".effect", effect)
    }
  }

  function setTriggerStrength(v) {
    setProfile("triggers.left.strength", v)
    setProfile("triggers.right.strength", v)
  }

  // Dragging a slider emits a value per mouse move. One output report per event
  // is fine over USB but floods the HID channel over Bluetooth, where the link
  // drops when the send buffer fills. So previews coalesce to one report every
  // ~90 ms, and skip the lightbar handover report — the profile commands that
  // bracket the drag already did it.
  function previewLightbar(hex, brightness) {
    if (!canControl) return
    _pendingHex = hex
    _pendingBrightness = brightness
    if (previewThrottle.running) return
    flushPreview()
    previewThrottle.start()
  }

  function flushPreview() {
    if (_pendingHex === "" || !canControl || preview.running) return
    preview.command = ["python3", helper].concat(deviceArgs())
      .concat(["--no-release", "lightbar", _pendingHex, "--brightness", String(Math.round(_pendingBrightness))])
    preview.running = true
    _pendingHex = ""
  }

  function reconnectBluetooth() {
    ctl(["reconnect"], function(code) { root.refresh() })
  }

  function applyProfile() {
    if (!connected) return
    ctl(["--all", "apply", "--accent", accentHex])
  }

  function resetProfile() {
    ctl(["--all", "profile", "reset", "--accent", accentHex], function() { root.refresh() })
  }

  function testRumble() {
    if (!connected) return
    ctl(deviceArgs().concat(["rumble", "--strong", "90", "--weak", "50", "--ms", "500"]))
  }

  function powerOff() {
    if (!bluetooth) return
    ctl(deviceArgs().concat(["poweroff"]), function() { root.refresh() })
  }

  function hueOf(hex) {
    var c = Qt.color(hex)
    return c.hsvHue < 0 ? 0 : c.hsvHue * 360
  }

  function hexFromHue(h) {
    return String(Qt.hsva(h / 360, 1, 1, 1)).substring(0, 7)
  }

  function shortMac(mac) {
    return String(mac || "").toUpperCase()
  }

  function fmtFirmware(c) {
    if (!c) return "—"
    var fw = c.firmware
    if (fw) return fw.version + " · update " + fw.updateVersion + " · built " + fw.buildDate
    return c.firmwareVersion || "—"
  }

  function deviceLabel(c, index) {
    return "P" + (index + 1) + " · " + (c.bus === "bluetooth" ? "BT" : "USB")
      + (c.battery && c.battery.capacity !== null ? " · " + c.battery.capacity + "%" : "")
  }

  // ---------- parsing ----------
  function parse(text) {
    var data = null
    try { data = JSON.parse(text) } catch (e) { data = null }
    if (!data || !data.controllers) {
      root.helperOk = false
      if (root.lastError === "") root.lastError = "dualsense-ctl returned no status"
      return
    }
    root.helperOk = true
    root.staleLinks = data.staleBluetooth || []
    var list = data.controllers
    var seen = {}
    var connectedNow = []
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      var key = String(c.mac || c.node)
      seen[key] = { capacity: c.battery ? c.battery.capacity : null, status: c.battery ? c.battery.status : "unknown" }
      var prev = root._prev[key]
      if (prev === undefined) {
        connectedNow.push(c)
        if (root._primed)
          root.notify(c.model + " connected", (c.bus === "bluetooth" ? "Bluetooth" : "USB")
            + (c.battery && c.battery.capacity !== null ? " · " + c.battery.capacity + "%" : ""), "low", root.glyph)
      } else {
        var cap = seen[key].capacity
        var st = seen[key].status
        if (root._primed && st === "full" && prev.status !== "full")
          root.notify(c.model + " fully charged", "You can unplug the cable", "low", "󰂅")
      }
      var lowNow = seen[key].capacity !== null && seen[key].capacity <= root.lowBattery
        && seen[key].status !== "charging" && seen[key].status !== "full"
      if (lowNow && !root._lowNotified[key]) {
        var ln = root._lowNotified; ln[key] = true; root._lowNotified = ln
        if (root._primed || prev === undefined)
          root.notify(c.model + " battery low", seen[key].capacity + "% · connect the cable", "critical", "󰂃")
      } else if (!lowNow && root._lowNotified[key] && (seen[key].status === "charging" || seen[key].capacity > root.lowBattery + 5)) {
        var ln2 = root._lowNotified; delete ln2[key]; root._lowNotified = ln2
      }
    }
    for (var k in root._prev) {
      if (seen[k] === undefined && root._primed) {
        root.notify("DualSense disconnected", "", "low", root.glyph)
        var ln3 = root._lowNotified; delete ln3[k]; root._lowNotified = ln3
      }
    }
    root._prev = seen
    root.controllers = list
    if (data.profile) root.profile = data.profile
    root.themeAccent = data.accent || ""
    var stillThere = false
    for (var j = 0; j < list.length; j++) if (list[j].mac === root.selectedMac) stillThere = true
    if (!stillThere) root.selectedMac = list.length > 0 ? String(list[0].mac) : ""
    // Newly connected controllers (and every controller at startup) get the profile.
    if (root.applyOnConnect)
      for (var n = 0; n < connectedNow.length; n++)
        if (connectedNow[n].access && connectedNow[n].access.hidraw)
          root.ctl(["--device", String(connectedNow[n].mac), "apply", "--accent", root.accentHex])
    root._primed = true
  }

  // The lightbar follows the theme accent when asked to.
  onAccentHexChanged: {
    if (_primed && canControl && lightbar.followTheme) ctl(["--all", "apply", "--accent", accentHex])
  }

  onOpenedChanged: {
    if (!opened) root.testerOn = false
  }

  implicitWidth: hideWhenDisconnected && !connected ? 0 : button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: !(hideWhenDisconnected && !connected)

  // ---------- processes ----------
  Process {
    id: poll
    command: ["python3", root.helper, "--profile", root.profileFile, "status", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.parse(text)
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.lastError = text.trim().split("\n").pop()
    }
    onExited: function(code) { if (code !== 0) root.helperOk = false }
  }

  Process {
    id: act
    property var job: null
    property string err: ""
    stderr: StdioCollector {
      onStreamFinished: act.err = text.trim().split("\n").pop() || ""
    }
    onExited: function(code, exitStatus) {
      root.busy = false
      if (code !== 0) {
        root.lastError = act.err || ("dualsense-ctl exited with " + code)
        if (code === 4) root.refresh()
      } else {
        root.lastError = ""
      }
      var job = act.job
      act.job = null
      if (job && job.after) job.after(code)
      root.pump()
      if (root._queue.length === 0) refreshSoon.restart()
    }
  }

  // Lightbar preview while dragging the hue/brightness sliders — fire and
  // forget, never queued, so the bar tracks the cursor.
  Process {
    id: preview
  }

  // Hot-plug: refresh the moment a hidraw device appears or disappears. With
  // no controller around this is what notices one arriving, so it is
  // restarted whenever it exits.
  Process {
    id: hotplug
    running: true
    command: ["udevadm", "monitor", "--udev", "--subsystem-match=hidraw"]
    stdout: SplitParser {
      onRead: function(line) {
        if (/\b(add|remove|bind|unbind)\b/.test(line)) refreshSoon.restart()
      }
    }
    onExited: hotplugRestart.start()
  }

  Timer {
    id: hotplugRestart
    interval: 5000
    onTriggered: hotplug.running = true
  }

  // Live input for the tester tab.
  Process {
    id: monitor
    running: root.opened && root.testerOn && root.connected && root.device.event
    command: ["python3", root.helper].concat(root.deviceArgs()).concat(["monitor", "--rate", "30"])
    stdout: SplitParser {
      onRead: function(line) {
        try { root.live = JSON.parse(line) } catch (e) {}
      }
    }
    onRunningChanged: if (!running) root.live = null
  }

  // A running Process keeps its original command, so switching controllers
  // left the tester reading the old one. Restart it on the new --device.
  readonly property string testerMac: connected ? String(device.mac) : ""
  onTesterMacChanged: if (monitor.running) {
    root.testerOn = false
    Qt.callLater(function() { root.testerOn = true })
  }

  // With nothing connected the only news is a controller arriving, which the
  // udev monitor reports at once, so polling idles at a minute; that still
  // catches a Bluetooth link going stale or away without a hidraw event.
  readonly property bool idle: controllers.length === 0 && staleLinks.length === 0

  Timer {
    interval: (root.opened ? 2 : root.idle ? Math.max(60, root.pollSeconds) : root.pollSeconds) * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshSoon
    interval: 700
    onTriggered: root.refresh()
  }

  Timer {
    id: previewThrottle
    interval: 90
    onTriggered: {
      if (root._pendingHex === "") return
      root.flushPreview()
      previewThrottle.start()
    }
  }

  IpcHandler {
    target: "atoslins.dualsense"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function apply(): void { root.applyProfile() }
    function rumble(): void { root.testRumble() }
    function poweroff(): void { root.powerOff() }
    function reconnect(): void { root.reconnectBluetooth() }
    function lightbar(color: string): void { root.setLightbarColor(String(color)) }
    function brightness(percent: int): void { root.setProfile("lightbar.brightness", Math.max(0, Math.min(100, percent))) }
    function player(number: int): void { root.setProfile("player.leds", Math.max(0, Math.min(7, number))) }
    function mic(state: string): void { root.setProfile("audio.micMuted", String(state) === "off" || String(state) === "mute") }
    function trigger(effect: string): void { root.setTriggerStrength(root.triggers.left.strength); root.setTrigger("both", String(effect)) }
    function followTheme(on: bool): void { root.setProfile("lightbar.followTheme", on) }
    function tab(name: string): void { root.tab = String(name); root.open() }
    function tester(on: bool): void { root.testerOn = on; if (on) root.open() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: {
      if (root.vertical || !root.connected) return root.glyph
      var t = root.glyph
      if (root.showPercent && root.capacity >= 0) t += " " + root.capacity + "%"
      if (root.charging) t += "󰉁"
      return t
    }
    active: root.low
    dimmed: !root.connected
    tooltipText: ""

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero ----------
        PanelHero {
          width: parent.width
          title: root.heroTitle
          meta: root.heroMeta
          detail: root.controllers.length > 1 ? root.controllers.length + " controllers" : ""
          foreground: root.fg
          fontFamily: root.face
          iconOpacity: root.connected ? 1 : 0.5
          iconComponent: Component {
            DualSenseShape {
              width: Style.space(76)
              compact: true
              foreground: root.connected ? root.fg : root.dim
              accent: Color.accent
              lightbarColor: root.connected ? root.lightbarColor : root.dim
              lightbarOn: root.connected && root.lightbar.enabled !== false
              ledPattern: root.connected ? root.ledPattern : 0
              micMuted: root.connected && root.audio.micMuted === true
            }
          }
          trailingControl: Component {
            Button {
              iconText: "󰑐"
              tooltipText: "Refresh"
              iconSpinning: poll.running || root.busy
              foreground: root.fg
              fontFamily: root.face
              bordered: true
              onClicked: root.refresh()
            }
          }
        }

        // ---------- Battery ----------
        Column {
          visible: root.connected
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Style.space(10)

            Rectangle {
              id: batteryTrack
              anchors.fill: parent
              radius: height / 2
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

              Rectangle {
                id: batteryFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.capacity >= 0 ? Math.max(height, parent.width * root.capacity / 100) : 0
                radius: parent.radius
                color: root.batteryColor
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 250 } }

                // Charging pulse.
                SequentialAnimation on opacity {
                  running: root.charging
                  loops: Animation.Infinite
                  onRunningChanged: if (!running) batteryFill.opacity = 1
                  NumberAnimation { from: 1; to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                  NumberAnimation { from: 0.45; to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(batteryText.implicitHeight, powerBtn.implicitHeight)

            Text {
              id: batteryText
              text: (root.charging ? "󰂄 " : root.low ? "󰂃 " : root.full ? "󰂅 " : "󰁹 ") + root.batteryLabel
              color: root.low ? root.urgent : root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              anchors.left: parent.left
              anchors.right: powerBtn.visible ? powerBtn.left : parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
            }

            Button {
              id: powerBtn
              visible: root.bluetooth
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰐥"
              text: "Power off"
              tooltipText: "Turn the controller off"
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.face
              bordered: true
              onClicked: root.powerOff()
            }
          }
        }

        // ---------- Not connected / no access ----------
        Column {
          visible: !root.connected || !root.canControl
          width: parent.width
          spacing: Style.space(6)

          Text {
            visible: !root.connected && root.helperOk && root.staleLinks.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Plug the controller in with a USB-C cable, or pair it over Bluetooth: hold Create + PS until the lightbar blinks, then pick “Wireless Controller” in the Bluetooth menu."
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.bodySmall
          }

          // Bluetooth still holds the link but the HID session is gone, so the
          // controller looks on while nothing can talk to it.
          Column {
            visible: !root.connected && root.staleLinks.length > 0
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "The controller is still linked over Bluetooth, but its input session dropped. Try Reconnect; if that does not take, press the PS button. Dropping the link is deliberately not attempted — a DualSense powers itself off when the host disconnects it."
              color: root.urgent
              font.family: root.face
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              iconText: "󰂱"
              text: root.busy ? "Reconnecting…" : "Reconnect"
              tooltipText: "Drop the stale link and connect again"
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.face
              bordered: true
              enabled: !root.busy
              onClicked: root.reconnectBluetooth()
            }
          }

          Text {
            visible: root.connected && !root.canControl
            width: parent.width
            wrapMode: Text.WordWrap
            text: "No permission to write to " + (root.device ? root.device.node : "the controller") + ". Run the plugin's udev/install-udev-rule as root (see README) or install the steam-devices package, then reconnect."
            color: root.urgent
            font.family: root.face
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: !root.helperOk
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.lastError || "The helper script failed to run. Is python3 installed?"
            color: root.urgent
            font.family: root.face
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---------- Controller picker (only with several) ----------
        ChipRow {
          visible: root.controllers.length > 1
          foreground: root.fg
          fontFamily: root.face
          options: {
            var out = []
            for (var i = 0; i < root.controllers.length; i++)
              out.push({ value: root.controllers[i].mac, label: root.deviceLabel(root.controllers[i], i), tooltip: root.shortMac(root.controllers[i].mac) })
            return out
          }
          value: root.selectedMac
          onChanged: function(v) { root.selectedMac = v }
        }

        PanelSeparator {
          visible: root.connected
          foreground: root.fg
        }

        // ---------- Tabs ----------
        ButtonGroup {
          visible: root.connected
          width: parent.width
          options: root.tabOptions
          value: root.tab
          foreground: root.fg
          fontFamily: root.face
          fontSize: Style.font.bodySmall
          onChanged: function(v) { root.tab = v }
        }

        // ================= LIGHTS =================
        Column {
          visible: root.connected && root.tab === "lights"
          width: parent.width
          spacing: Style.space(10)
          enabled: root.canControl
          opacity: root.canControl ? 1 : 0.5

          PanelSectionHeader {
            text: "LIGHTBAR"
            foreground: root.fg
            fontFamily: root.face
          }

          // Preview strip
          Rectangle {
            width: parent.width
            height: Style.space(12)
            radius: height / 2
            color: root.lightbar.enabled !== false ? root.lightbarColor : "transparent"
            border.width: root.lightbar.enabled !== false ? 0 : 1
            border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)
            Behavior on color { ColorAnimation { duration: 200 } }
          }

          // Swatches + theme accent
          Flow {
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.swatches

              Rectangle {
                required property var modelData
                readonly property bool current: !root.lightbar.followTheme && String(root.lightbar.color).toLowerCase() === String(modelData).toLowerCase()
                width: Style.space(26)
                height: width
                radius: width / 2
                color: modelData
                border.width: current ? 3 : 1
                border.color: current ? root.fg : Qt.rgba(0, 0, 0, 0.35)
                scale: swatchMouse.containsMouse ? 1.12 : 1
                Behavior on scale { NumberAnimation { duration: 100 } }

                MouseArea {
                  id: swatchMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setLightbarColor(String(parent.modelData))
                }
              }
            }

            Rectangle {
              readonly property bool current: root.lightbar.followTheme === true
              width: Style.space(26)
              height: width
              radius: width / 2
              color: Color.accent
              border.width: current ? 3 : 1
              border.color: current ? root.fg : Qt.rgba(0, 0, 0, 0.35)
              scale: themeMouse.containsMouse ? 1.12 : 1
              Behavior on scale { NumberAnimation { duration: 100 } }

              Text {
                anchors.centerIn: parent
                text: "󰏘"
                color: Color.background
                font.family: root.face
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: themeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setProfile("lightbar.followTheme", true)
              }
            }
          }

          SliderRow {
            bar: root.bar
            label: "Hue"
            valueText: root.lightbarHex.toUpperCase()
            minimum: 0
            maximum: 359
            step: 1
            value: root.hueOf(root.lightbarHex)
            foreground: root.fg
            fontFamily: root.face
            dimmed: root.lightbar.followTheme === true
            onMoved: function(v) { root.previewLightbar(root.hexFromHue(v), root.lightbar.brightness) }
            onReleased: function(v) { root.setLightbarColor(root.hexFromHue(v)) }
          }

          SliderRow {
            bar: root.bar
            label: "Brightness"
            valueText: Math.round(Number(root.lightbar.brightness)) + "%"
            minimum: 0
            maximum: 100
            step: 5
            value: Number(root.lightbar.brightness)
            foreground: root.fg
            fontFamily: root.face
            onMoved: function(v) { root.previewLightbar(root.lightbarHex, v) }
            onReleased: function(v) { root.setProfile("lightbar.brightness", Math.round(v)) }
          }

          Toggle {
            width: parent.width
            label: "Follow theme accent"
            description: "Lightbar takes the Omarchy theme's accent color"
            checked: root.lightbar.followTheme === true
            foreground: root.fg
            fontFamily: root.face
            onClicked: root.setProfile("lightbar.followTheme", !(root.lightbar.followTheme === true))
          }

          Toggle {
            width: parent.width
            label: "Lightbar"
            description: "Turn the lightbar off entirely"
            checked: root.lightbar.enabled !== false
            foreground: root.fg
            fontFamily: root.face
            onClicked: root.setProfile("lightbar.enabled", !(root.lightbar.enabled !== false))
          }

          PanelSectionHeader {
            text: "PLAYER LEDS"
            foreground: root.fg
            fontFamily: root.face
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(ledRow.implicitHeight, ledGroup.implicitHeight)

            // Five white dots mirroring the pattern on the device.
            Row {
              id: ledRow
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              Repeater {
                model: 5
                Rectangle {
                  required property int index
                  readonly property bool lit: (root.ledPattern & (1 << index)) !== 0
                  width: Style.space(8)
                  height: width
                  radius: width / 2
                  color: lit ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)
                  Behavior on color { ColorAnimation { duration: 150 } }
                }
              }
            }

            ButtonGroup {
              id: ledGroup
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              options: [{ value: "0", label: "Off" }, "1", "2", "3", "4", "5"]
              value: String(root.player.leds)
              foreground: root.fg
              fontFamily: root.face
              fontSize: Style.font.bodySmall
              onChanged: function(v) { root.setProfile("player.leds", parseInt(v, 10)) }
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(brightLabel.implicitHeight, brightGroup.implicitHeight)

            Text {
              id: brightLabel
              text: "LED brightness"
              color: root.fg
              font.family: root.face
              font.pixelSize: Style.font.bodySmall
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            ButtonGroup {
              id: brightGroup
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              options: [{ value: "high", label: "High" }, { value: "medium", label: "Medium" }, { value: "low", label: "Low" }]
              value: String(root.player.brightness)
              foreground: root.fg
              fontFamily: root.face
              fontSize: Style.font.bodySmall
              onChanged: function(v) { root.setProfile("player.brightness", v) }
            }
          }
        }

        // ================= FEEL =================
        Column {
          visible: root.connected && root.tab === "feel"
          width: parent.width
          spacing: Style.space(10)
          enabled: root.canControl
          opacity: root.canControl ? 1 : 0.5

          PanelSectionHeader {
            text: "ADAPTIVE TRIGGERS"
            foreground: root.fg
            fontFamily: root.face
          }

          Text {
            text: root.linkTriggers ? "L2 + R2" : "L2"
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          ChipRow {
            foreground: root.fg
            fontFamily: root.face
            options: root.triggerOptions
            value: String(root.triggers.left.effect)
            onChanged: function(v) { root.setTrigger("left", v) }
          }

          Text {
            visible: !root.linkTriggers
            text: "R2"
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          ChipRow {
            visible: !root.linkTriggers
            foreground: root.fg
            fontFamily: root.face
            options: root.triggerOptions
            value: String(root.triggers.right.effect)
            onChanged: function(v) { root.setTrigger("right", v) }
          }

          SliderRow {
            bar: root.bar
            label: "Effect strength"
            valueText: Number(root.triggers.left.strength) + " / 8"
            minimum: 1
            maximum: 8
            step: 1
            tickCount: 8
            value: Number(root.triggers.left.strength)
            foreground: root.fg
            fontFamily: root.face
            onReleased: function(v) { root.setTriggerStrength(Math.round(v)) }
          }

          Toggle {
            width: parent.width
            label: "Same effect on both triggers"
            description: "Off lets L2 and R2 take different effects"
            checked: root.linkTriggers
            foreground: root.fg
            fontFamily: root.face
            onClicked: root.linkTriggers = !root.linkTriggers
          }

          PanelSectionHeader {
            text: "MOTORS"
            foreground: root.fg
            fontFamily: root.face
          }

          SliderRow {
            bar: root.bar
            label: "Rumble strength"
            valueText: (8 - Number(root.motors.rumble)) + " / 8"
            minimum: 1
            maximum: 8
            step: 1
            tickCount: 8
            value: 8 - Number(root.motors.rumble)
            foreground: root.fg
            fontFamily: root.face
            onReleased: function(v) { root.setProfile("motors.rumble", 8 - Math.round(v)) }
          }

          SliderRow {
            bar: root.bar
            label: "Trigger motor strength"
            valueText: (8 - Number(root.motors.trigger)) + " / 8"
            minimum: 1
            maximum: 8
            step: 1
            tickCount: 8
            value: 8 - Number(root.motors.trigger)
            foreground: root.fg
            fontFamily: root.face
            onReleased: function(v) { root.setProfile("motors.trigger", 8 - Math.round(v)) }
          }
        }

        // Outside the Feel column: force feedback goes through the gamepad's
        // input node, which works without hidraw access.
        Button {
          visible: root.connected && root.tab === "feel"
          enabled: root.canRumble
          opacity: enabled ? 1 : 0.5
          iconText: "󰕦"
          text: "Test rumble"
          tooltipText: "Half a second on both motors, through the same force-feedback path games use"
          fontSize: Style.font.bodySmall
          foreground: root.fg
          fontFamily: root.face
          bordered: true
          onClicked: root.testRumble()
        }

        // ================= AUDIO =================
        Column {
          visible: root.connected && root.tab === "audio"
          width: parent.width
          spacing: Style.space(10)
          enabled: root.canControl
          opacity: root.canControl ? 1 : 0.5

          PanelSectionHeader {
            text: "MICROPHONE"
            foreground: root.fg
            fontFamily: root.face
          }

          Toggle {
            width: parent.width
            label: "Mute microphone"
            description: root.audio.micMuted ? "The built-in mic is muted" : "The built-in mic is live"
            checked: root.audio.micMuted === true
            foreground: root.fg
            fontFamily: root.face
            onClicked: root.setProfile("audio.micMuted", !(root.audio.micMuted === true))
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(micLedLabel.implicitHeight, micLedGroup.implicitHeight)

            Text {
              id: micLedLabel
              text: "Mute LED"
              color: root.fg
              font.family: root.face
              font.pixelSize: Style.font.bodySmall
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            ButtonGroup {
              id: micLedGroup
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              options: root.micLedOptions
              value: String(root.audio.micLed)
              foreground: root.fg
              fontFamily: root.face
              fontSize: Style.font.bodySmall
              onChanged: function(v) { root.setProfile("audio.micLed", v) }
            }
          }

          SliderRow {
            bar: root.bar
            label: "Mic gain"
            valueText: root.audio.micVolume === null || root.audio.micVolume === undefined ? "controller default" : root.audio.micVolume + "%"
            minimum: 0
            maximum: 100
            step: 5
            value: root.audio.micVolume === null || root.audio.micVolume === undefined ? 100 : Number(root.audio.micVolume)
            foreground: root.fg
            fontFamily: root.face
            dimmed: root.audio.micVolume === null || root.audio.micVolume === undefined
            onReleased: function(v) { root.setProfile("audio.micVolume", Math.round(v)) }
          }

          PanelSectionHeader {
            text: "SPEAKER & HEADPHONES"
            foreground: root.fg
            fontFamily: root.face
          }

          ChipRow {
            foreground: root.fg
            fontFamily: root.face
            options: root.speakerOptions
            value: root.audio.speaker === null || root.audio.speaker === undefined ? "" : String(root.audio.speaker)
            onChanged: function(v) { root.setProfile("audio.speaker", v === "" ? null : v) }
          }

          SliderRow {
            bar: root.bar
            label: "Volume"
            valueText: root.audio.volume === null || root.audio.volume === undefined ? "controller default" : root.audio.volume + "%"
            minimum: 0
            maximum: 100
            step: 5
            value: root.audio.volume === null || root.audio.volume === undefined ? 70 : Number(root.audio.volume)
            foreground: root.fg
            fontFamily: root.face
            dimmed: root.audio.volume === null || root.audio.volume === undefined
            onReleased: function(v) { root.setProfile("audio.volume", Math.round(v)) }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Audio plays through the controller when it is the active output. The route decides whether the jack, the built-in speaker or both carry it; “Default” leaves the controller's own choice alone."
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.caption
          }
        }

        // ================= TEST =================
        Column {
          visible: root.connected && root.tab === "test"
          width: parent.width
          spacing: Style.space(10)

          Toggle {
            width: parent.width
            label: "Live input"
            description: root.testerOn ? "Reading the controller · press anything" : "Show sticks, triggers, buttons, touchpad and motion as you use them"
            checked: root.testerOn
            foreground: root.fg
            fontFamily: root.face
            onClicked: root.testerOn = !root.testerOn
          }

          GamepadTester {
            visible: root.testerOn
            width: parent.width
            live: root.live
            foreground: root.fg
            accent: Color.accent
            lightbarColor: root.lightbarColor
            lightbarOn: root.lightbar.enabled !== false
            micMuted: root.audio.micMuted === true
            ledPattern: root.ledPattern
            fontFamily: root.face
          }

          Text {
            visible: root.testerOn && root.live && root.live.battery && root.live.battery.capacity !== null
            text: "Battery " + (root.live && root.live.battery ? root.live.battery.capacity + "% · " + root.live.battery.status : "")
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.caption
          }
        }

        // ================= INFO =================
        Column {
          visible: root.connected && root.tab === "info"
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "CONTROLLER"
            foreground: root.fg
            fontFamily: root.face
          }

          Repeater {
            model: root.device ? [
              { label: "Model", value: root.device.model },
              { label: "Connection", value: root.bluetooth ? "Bluetooth" : "USB-C" },
              { label: "Address", value: root.shortMac(root.device.mac) },
              { label: "Firmware", value: root.fmtFirmware(root.device) },
              { label: "Hardware", value: root.device.hardwareVersion || "—" },
              { label: "Driver", value: root.device.driver || "—" },
              { label: "HID node", value: root.device.node + (root.canControl ? "" : " · no access") },
              { label: "Input node", value: root.device.event || "—" },
              { label: "Motion", value: (root.device.motion || "—") + (root.device.motion && !(root.device.access && root.device.access.motion) ? " · no access" : "") },
              { label: "Touchpad", value: (root.device.touchpad || "—") + (root.device.touchpad && !(root.device.access && root.device.access.touchpad) ? " · no access" : "") },
              { label: "Profile", value: root.profileSetting }
            ] : []

            Item {
              required property var modelData
              width: parent.width
              implicitHeight: Math.max(infoLabel.implicitHeight, infoValue.implicitHeight)

              Text {
                id: infoLabel
                text: modelData.label
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.bodySmall
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(96)
              }

              Text {
                id: infoValue
                text: String(modelData.value)
                color: modelData.label === "HID node" && !root.canControl ? root.urgent : root.fg
                font.family: root.face
                font.pixelSize: Style.font.bodySmall
                anchors.left: infoLabel.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideMiddle
              }
            }
          }

          Text {
            visible: root.lastError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.lastError
            color: root.urgent
            font.family: root.face
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "IPC: omarchy-shell atoslins.dualsense lightbar '#ff4000' · player 2 · rumble · apply · poweroff"
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- Footer ----------
        PanelSeparator {
          visible: root.connected
          foreground: root.fg
        }

        Row {
          visible: root.connected
          spacing: Style.space(6)

          Button {
            iconText: "󰑐"
            text: "Reapply profile"
            tooltipText: "Send every saved setting to the controller again"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.face
            bordered: true
            enabled: root.canControl
            onClicked: root.applyProfile()
          }

          Button {
            iconText: "󰦛"
            text: "Reset"
            tooltipText: "Back to the default profile"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.face
            bordered: true
            onClicked: root.resetProfile()
          }

          Button {
            visible: root.bluetooth
            iconText: "󰂲"
            text: "Disconnect"
            tooltipText: "Drop the Bluetooth link without powering off"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.face
            bordered: true
            onClicked: root.ctl(root.deviceArgs().concat(["disconnect"]), function() { root.refresh() })
          }
        }
      }
    }
  }
}
