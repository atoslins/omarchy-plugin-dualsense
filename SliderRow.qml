import QtQuick
import qs.Commons
import qs.Ui

// Label on the left, current value on the right, slider underneath.
Column {
  id: root

  property var bar: null
  property string label: ""
  property string valueText: ""
  property real value: 0
  property real minimum: 0
  property real maximum: 100
  property real step: 1
  property bool integer: true
  property int tickCount: 0
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool dimmed: false

  signal moved(real value)
  signal released(real value)

  readonly property color dim: Qt.darker(foreground, 1.4)

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(2)
  opacity: dimmed ? 0.55 : 1

  Item {
    width: parent.width
    implicitHeight: Math.max(labelText.implicitHeight, valueLabel.implicitHeight)

    Text {
      id: labelText
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.left: parent.left
      anchors.right: valueLabel.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }

    Text {
      id: valueLabel
      text: root.valueText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.0
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  Item {
    width: parent.width
    implicitHeight: slider.implicitHeight

    PanelSlider {
      id: slider
      bar: root.bar
      anchors.fill: parent
      anchors.leftMargin: Style.space(4)
      anchors.rightMargin: Style.space(4)
      minimum: root.minimum
      maximum: root.maximum
      step: root.step
      integer: root.integer
      tickCount: root.tickCount
      value: root.value
      onMoved: function(v) { root.moved(v) }
      onReleased: function(v) { root.released(v) }
    }
  }
}
