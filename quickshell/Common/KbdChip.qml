import QtQuick
import qs.Theme

// Bordered keycap chip -- "esc" in the command window header, "↵" on its
// selected result row. `accent` switches it to the crimson variant.
Rectangle {
  id: chip

  property alias text: label.text
  property bool accent: false
  // The header chip pads 7px, the row chip 8px; nothing else varies.
  property int hPadding: 7

  implicitWidth: label.implicitWidth + hPadding * 2
  implicitHeight: label.implicitHeight + 6
  radius: Theme.radiusKbd
  color: "transparent"
  border.width: 1
  border.color: chip.accent ? Theme.alpha(Theme.accent, 0.4) : Theme.hairlineStrong

  Text {
    id: label
    anchors.centerIn: parent
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: chip.accent ? Theme.accentSoft : Theme.text3
  }
}
