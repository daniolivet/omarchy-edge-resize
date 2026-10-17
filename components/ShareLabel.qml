import QtQuick
import qs.Commons

// Live share of each window while dragging: side by side for a vertical edge,
// stacked top/bottom for a horizontal one, next to the pill.
Rectangle {
  id: shareLabel

  required property bool vertical
  required property int share   // percent of the left/top window
  required property real axisCenter
  required property real crossCenter
  required property real gapSize

  width: label.implicitWidth + Style.space(24)
  height: label.implicitHeight + Style.space(14)
  radius: Math.max(Style.cornerRadius, Style.space(8))
  color: Util.alpha(Color.background, 0.97)
  border.color: Color.accent
  border.width: Math.max(1, Style.space(2))
  x: vertical ? axisCenter + gapSize / 2 + Style.space(10) : crossCenter + Style.space(50)
  y: vertical ? crossCenter - height / 2 : axisCenter - height / 2

  Text {
    id: label
    anchors.centerIn: parent
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.StyledText
    font.weight: Font.DemiBold
    lineHeight: 1.1
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    color: Color.popups.text
    text: {
      const separator = `<font color="${Color.accent}">·</font>`
      const other = 100 - shareLabel.share
      return shareLabel.vertical ? `${shareLabel.share}%&nbsp;&nbsp;${separator}&nbsp;&nbsp;${other}%`
                                 : `${shareLabel.share}%<br>${separator}<br>${other}%`
    }
  }
}
