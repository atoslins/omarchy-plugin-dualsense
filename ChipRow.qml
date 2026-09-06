import QtQuick
import qs.Commons
import qs.Ui

// A wrapping row of small selectable buttons — a ButtonGroup that can take
// more options than fit on one line (trigger effects, audio routes).
Flow {
  id: root

  // [{ value, label, icon?, tooltip? }] or plain strings
  property var options: []
  property string value: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.bodySmall

  signal changed(string value)

  function optionValue(o) { return (o && typeof o === "object") ? String(o.value) : String(o) }
  function optionLabel(o) { return (o && typeof o === "object" && o.label !== undefined) ? String(o.label) : String(o) }

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(6)

  Repeater {
    model: root.options

    Button {
      required property var modelData
      text: root.optionLabel(modelData)
      iconText: (modelData && typeof modelData === "object" && modelData.icon) ? String(modelData.icon) : ""
      tooltipText: (modelData && typeof modelData === "object" && modelData.tooltip) ? String(modelData.tooltip) : ""
      selected: root.optionValue(modelData) === root.value
      bordered: true
      fontSize: root.fontSize
      foreground: root.foreground
      fontFamily: root.fontFamily
      opacity: root.enabled ? 1 : 0.5
      onClicked: if (root.enabled) root.changed(root.optionValue(modelData))
    }
  }
}
