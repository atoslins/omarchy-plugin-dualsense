import QtQuick
import qs.Commons

// Live view of what the controller reports through evdev, drawn on the
// DualSense silhouette: every button lights, the sticks move, the triggers
// fill, touches show on the touchpad, and the motion sensors read out below.
// Fed by `dualsense-ctl monitor` JSON lines.
Item {
  id: root

  property var live: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color lightbarColor: "#1e64ff"
  property bool lightbarOn: true
  property bool micMuted: false
  property int ledPattern: 4
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color idle: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  readonly property color outline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.35)
  readonly property bool hasMotion: live && live.sources && live.sources.motion === true
  readonly property bool hasTouch: live && live.sources && live.sources.touchpad === true

  function axis(name) { return live && typeof live[name] === "number" ? live[name] : 0 }

  width: parent ? parent.width : implicitWidth
  implicitHeight: column.implicitHeight

  component Meter: Item {
    property string label: ""
    property real value: 0   // -1 .. 1
    property string unit: ""
    width: parent ? parent.width : 100
    height: Style.space(12)

    Text {
      id: meterLabel
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      width: Style.space(40)
      anchors.verticalCenter: parent.verticalCenter
    }

    Rectangle {
      id: meterTrack
      anchors.left: meterLabel.right
      anchors.right: meterValue.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(4)
      color: root.idle
      radius: height / 2

      Rectangle {
        readonly property real v: Math.max(-1, Math.min(1, parent.parent.value))
        x: v >= 0 ? meterTrack.width / 2 : meterTrack.width / 2 + v * meterTrack.width / 2
        width: Math.abs(v) * meterTrack.width / 2
        height: parent.height
        radius: parent.radius
        color: root.accent
      }
      Rectangle { width: 1; height: parent.height + 4; y: -2; x: parent.width / 2; color: root.outline }
    }

    Text {
      id: meterValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: parent.unit
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      width: Style.space(64)
      horizontalAlignment: Text.AlignRight
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    DualSenseShape {
      width: parent.width
      foreground: root.foreground
      accent: root.accent
      lightbarColor: root.lightbarColor
      lightbarOn: root.lightbarOn
      micMuted: root.micMuted
      ledPattern: root.ledPattern
      live: root.live
    }

    // Numeric readout under the drawing.
    Grid {
      width: parent.width
      columns: 4
      columnSpacing: Style.space(8)

      Repeater {
        model: [
          { label: "L3", value: root.axis("lx").toFixed(2) + ", " + root.axis("ly").toFixed(2) },
          { label: "R3", value: root.axis("rx").toFixed(2) + ", " + root.axis("ry").toFixed(2) },
          { label: "L2", value: Math.round(root.axis("l2") * 100) + "%" },
          { label: "R2", value: Math.round(root.axis("r2") * 100) + "%" }
        ]
        Row {
          required property var modelData
          spacing: Style.space(4)
          Text { text: modelData.label; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          Text { text: modelData.value; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        }
      }
    }

    // Motion sensors — only when the motion node is readable.
    Column {
      visible: root.hasMotion
      width: parent.width
      spacing: Style.space(2)
      readonly property var gyro: root.live && root.live.gyro ? root.live.gyro : [0, 0, 0]
      readonly property var accel: root.live && root.live.accel ? root.live.accel : [0, 0, 0]

      Meter { label: "gyro x"; value: parent.gyro[0] / 500; unit: parent.gyro[0].toFixed(0) + " °/s" }
      Meter { label: "gyro y"; value: parent.gyro[1] / 500; unit: parent.gyro[1].toFixed(0) + " °/s" }
      Meter { label: "gyro z"; value: parent.gyro[2] / 500; unit: parent.gyro[2].toFixed(0) + " °/s" }
      Meter { label: "accel x"; value: parent.accel[0] / 2; unit: parent.accel[0].toFixed(2) + " g" }
      Meter { label: "accel y"; value: parent.accel[1] / 2; unit: parent.accel[1].toFixed(2) + " g" }
      Meter { label: "accel z"; value: parent.accel[2] / 2; unit: parent.accel[2].toFixed(2) + " g" }
    }

    Text {
      visible: root.live && !(root.hasMotion && root.hasTouch)
      width: parent.width
      wrapMode: Text.WordWrap
      text: (!root.hasMotion && !root.hasTouch ? "Motion sensors and touchpad" : !root.hasMotion ? "Motion sensors" : "Touchpad")
        + " need read access to their input nodes — install the udev rule from the plugin's udev/ folder (see README) and reconnect."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      text: "Controller art: dualshock-tools · MIT"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
    }

    Text {
      visible: !root.live
      text: "Waiting for the controller…"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
