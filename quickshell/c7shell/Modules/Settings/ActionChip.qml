import QtQuick
import qs.Theme

// The bordered chip 2a uses for row and section actions — "+ add tunnel",
// "rescan", "pair", "forget". Crimson by default; `accented: false` gives the
// neutral variant for anything that is not the row's primary action.
Rectangle {
  id: root

  property string text: ""
  property bool accented: true

  signal triggered()

  implicitWidth: label.implicitWidth + 20
  implicitHeight: 20
  radius: Theme.radiusChip
  color: mouse.containsMouse
    ? (root.accented ? Theme.accentFillSoft : Theme.surface04)
    : "transparent"
  border.width: 1
  border.color: root.accented ? Theme.accentBorder : Theme.hairlineStrong

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: root.accented ? Theme.accentSoft : Theme.alpha(Theme.text, 0.5)
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.triggered()
  }
}
