import QtQuick
import QtQuick.Shapes
import qs.Commons
import "DualSenseArt.js" as Art

// The DualSense line art from dualshock-tools (MIT, see THIRD_PARTY_NOTICES.md)
// rendered with QtQuick Shapes so every part takes theme colors: the lightbar
// glows in the real lightbar color, the five LEDs show the player pattern,
// and with `live` input every button lights, the sticks move, the triggers
// fill and touches land on the touchpad. `compact` is the icon-sized variant.
Item {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color lightbarColor: "#1e64ff"
  property bool lightbarOn: true
  property bool compact: false
  property bool micMuted: false
  property int ledPattern: 4
  property var live: null

  readonly property real designWidth: Art.art.viewBox[0]
  readonly property real designHeight: Art.art.viewBox[1]
  readonly property real s: width / designWidth
  readonly property real k: Art.art.scale * s          // SVG units -> screen px
  readonly property real hairline: (compact ? 1.4 : 0) / Math.max(0.0001, k)

  readonly property color line: Qt.rgba(foreground.r, foreground.g, foreground.b, compact ? 0.92 : 0.78)
  readonly property color idle: Qt.rgba(foreground.r, foreground.g, foreground.b, compact ? 0.0 : 0.10)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06)
  readonly property color ledOff: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property var buttons: live && live.buttons ? live.buttons : ({})

  function pressed(name) { return buttons[name] === true }
  function axis(name) { return live && typeof live[name] === "number" ? live[name] : 0 }
  function fill(name) { return pressed(name) ? accent : idle }
  function triggerFill(name) {
    var v = Math.max(axis(name), pressed(name) ? 1 : 0)
    return v > 0 ? Qt.rgba(accent.r, accent.g, accent.b, 0.12 + 0.88 * v) : idle
  }

  implicitHeight: width * designHeight / designWidth
  height: implicitHeight

  component Outline: ShapePath {
    property string d: ""
    fillColor: root.line
    strokeColor: "transparent"
    fillRule: ShapePath.WindingFill
    PathSvg { path: d }
  }

  component Infill: ShapePath {
    property string d: ""
    strokeColor: "transparent"
    fillRule: ShapePath.WindingFill
    PathSvg { path: d }
  }

  Item {
    id: art
    transform: [
      Scale { xScale: root.k; yScale: root.k },
      Translate { x: Art.art.tx * root.s; y: Art.art.ty * root.s }
    ]

    // ---- lightbar glow (behind the body so it bleeds softly) ----
    Shape {
      preferredRendererType: Shape.CurveRenderer
      opacity: root.lightbarOn ? 1 : 0

      ShapePath {
        fillColor: "transparent"
        strokeColor: Qt.rgba(root.lightbarColor.r, root.lightbarColor.g, root.lightbarColor.b, 0.28)
        strokeWidth: (root.compact ? 7 : 12) / root.k
        capStyle: ShapePath.RoundCap
        startX: 246; startY: 168
        PathCubic { control1X: 231; control1Y: 205; control2X: 231; control2Y: 275; x: 246; y: 310 }
      }
      ShapePath {
        fillColor: "transparent"
        strokeColor: Qt.rgba(root.lightbarColor.r, root.lightbarColor.g, root.lightbarColor.b, 0.28)
        strokeWidth: (root.compact ? 7 : 12) / root.k
        capStyle: ShapePath.RoundCap
        startX: 660; startY: 168
        PathCubic { control1X: 675; control1Y: 205; control2X: 675; control2Y: 275; x: 660; y: 310 }
      }
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.lightbarColor
        strokeWidth: (root.compact ? 3 : 4.5) / root.k
        capStyle: ShapePath.RoundCap
        startX: 246; startY: 168
        PathCubic { control1X: 231; control1Y: 205; control2X: 231; control2Y: 275; x: 246; y: 310 }
      }
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.lightbarColor
        strokeWidth: (root.compact ? 3 : 4.5) / root.k
        capStyle: ShapePath.RoundCap
        startX: 660; startY: 168
        PathCubic { control1X: 675; control1Y: 205; control2X: 675; control2Y: 275; x: 660; y: 310 }
      }
    }

    // ---- infills (under the outlines) ----
    Shape {
      preferredRendererType: Shape.CurveRenderer

      Infill { d: Art.art.trackpadInfill; fillColor: root.live && root.live.touchClick ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) : root.faint }
      Infill { d: Art.art.infills.l2; fillColor: root.triggerFill("l2") }
      Infill { d: Art.art.infills.r2; fillColor: root.triggerFill("r2") }
      Infill { d: Art.art.infills.l1; fillColor: root.fill("l1") }
      Infill { d: Art.art.infills.r1; fillColor: root.fill("r1") }
      Infill { d: Art.art.infills.create; fillColor: root.fill("create") }
      Infill { d: Art.art.infills.options; fillColor: root.fill("options") }
      Infill { d: Art.art.infills.up; fillColor: root.axis("dy") < 0 ? root.accent : root.idle }
      Infill { d: Art.art.infills.down; fillColor: root.axis("dy") > 0 ? root.accent : root.idle }
      Infill { d: Art.art.infills.left; fillColor: root.axis("dx") < 0 ? root.accent : root.idle }
      Infill { d: Art.art.infills.right; fillColor: root.axis("dx") > 0 ? root.accent : root.idle }
      Infill { d: Art.art.infills.triangle; fillColor: root.fill("triangle") }
      Infill { d: Art.art.infills.cross; fillColor: root.fill("cross") }
      Infill { d: Art.art.infills.circle; fillColor: root.fill("circle") }
      Infill { d: Art.art.infills.square; fillColor: root.fill("square") }
      Infill { d: Art.art.infills.ps; fillColor: root.fill("ps") }
      Infill { d: Art.art.infills.mute; fillColor: root.micMuted ? Qt.rgba(1, 0.55, 0.1, 0.95) : root.idle }
    }

    // ---- body and outlines ----
    Shape {
      preferredRendererType: Shape.CurveRenderer

      Outline { d: Art.art.body; strokeColor: root.compact ? root.line : "transparent"; strokeWidth: root.hairline; joinStyle: ShapePath.RoundJoin }
      Outline { d: Art.art.trackpadOutline; strokeColor: root.compact ? root.line : "transparent"; strokeWidth: root.hairline }
      Outline { d: Art.art.l3Surround; strokeColor: root.compact ? root.line : "transparent"; strokeWidth: root.hairline }
      Outline { d: Art.art.r3Surround; strokeColor: root.compact ? root.line : "transparent"; strokeWidth: root.hairline }
    }

    Shape {
      visible: !root.compact
      preferredRendererType: Shape.CurveRenderer

      Outline { d: Art.art.outlines.l1 }
      Outline { d: Art.art.outlines.r1 }
      Outline { d: Art.art.outlines.l2 }
      Outline { d: Art.art.outlines.r2 }
      Outline { d: Art.art.outlines.create }
      Outline { d: Art.art.outlines.options }
      Outline { d: Art.art.outlines.up }
      Outline { d: Art.art.outlines.down }
      Outline { d: Art.art.outlines.left }
      Outline { d: Art.art.outlines.right }
      Outline { d: Art.art.outlines.triangle }
      Outline { d: Art.art.outlines.cross }
      Outline { d: Art.art.outlines.circle }
      Outline { d: Art.art.outlines.square }
      Outline { d: Art.art.outlines.ps }
      Outline { d: Art.art.outlines.mute }
    }

    // ---- player LEDs (the five dots under the touchpad) ----
    Repeater {
      model: Art.art.leds
      Rectangle {
        required property var modelData
        required property int index
        readonly property bool lit: ((root.ledPattern >> index) & 1) === 1
        x: modelData[0] - modelData[2] * 1.4
        y: modelData[1] - modelData[2] * 1.4
        width: modelData[2] * 2.8
        height: width
        radius: width / 2
        color: lit ? root.foreground : root.ledOff
        Behavior on color { ColorAnimation { duration: 150 } }
      }
    }

    // ---- sticks: cap moves with the axis, lights on click ----
    Shape {
      preferredRendererType: Shape.CurveRenderer
      transform: Translate { x: root.axis("lx") * 20; y: root.axis("ly") * 20 }
      Infill { d: Art.art.l3.infill; fillColor: root.pressed("l3") ? root.accent : (root.live ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35) : root.faint) }
      Outline { d: Art.art.l3.outline; strokeColor: root.compact ? root.line : "transparent"; strokeWidth: root.hairline }
    }
    Shape {
      preferredRendererType: Shape.CurveRenderer
      transform: Translate { x: root.axis("rx") * 20; y: root.axis("ry") * 20 }
      Infill { d: Art.art.r3.infill; fillColor: root.pressed("r3") ? root.accent : (root.live ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35) : root.faint) }
      Outline { d: Art.art.r3.outline; strokeColor: root.compact ? root.line : "transparent"; strokeWidth: root.hairline }
    }

    // ---- touches on the touchpad ----
    Repeater {
      model: root.live && root.live.touches ? root.live.touches : []
      Rectangle {
        required property var modelData
        readonly property var box: Art.art.trackpadBox
        width: 26; height: 26; radius: 13
        color: root.accent
        x: box[0] + 12 + modelData.x * (box[2] - box[0] - 24 - width)
        y: box[1] + 12 + modelData.y * (box[3] - box[1] - 24 - height)
      }
    }
  }
}
