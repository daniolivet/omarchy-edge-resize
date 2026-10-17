import QtQuick
import qs.Commons

// The handle: a pill centered on the gap, visible on hover or drag.
Rectangle {
  required property bool vertical
  required property bool hovered
  required property bool pressed
  required property real axisCenter
  required property real crossCenter

  readonly property bool active: hovered || pressed
  readonly property real length: Style.space(80)   // along the edge
  readonly property real thickness: Style.space(pressed ? 8 : 6)
  width: vertical ? thickness : length
  height: vertical ? length : thickness
  radius: Math.min(width, height) / 2
  color: Color.accent
  opacity: active ? 0.95 : 0
  x: vertical ? axisCenter - width / 2 : crossCenter - width / 2
  y: vertical ? crossCenter - height / 2 : axisCenter - height / 2
  Behavior on opacity { NumberAnimation { duration: 120 } }
}
