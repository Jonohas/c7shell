import QtQuick
import qs.Theme

// The r14 surface every settings page groups its content into (2a/2b: eth card,
// accent card, sliders card, wallpaper card). Children stack in a column and
// the card takes its height from them.
Rectangle {
  id: root

  default property alias content: body.data
  property alias spacing: body.spacing
  // 2a/2b cards are padded 12px 14px; the row-list pages inset less on the
  // sides so their rows can bleed to the card edge like the popovers do.
  property int padV: 12
  property int padH: 14

  implicitHeight: body.implicitHeight + root.padV * 2
  radius: Theme.radiusCard
  color: Theme.surface04
  border.width: 1
  border.color: Theme.hairline

  Column {
    id: body

    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      leftMargin: root.padH
      rightMargin: root.padH
      topMargin: root.padV
    }
    spacing: 10
  }
}
