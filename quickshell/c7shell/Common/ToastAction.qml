import QtQuick
import qs.Theme

// One word of action text on a toast card: "open", "later", "review now". The
// capture card and the update toast each had a private copy, identical apart
// from the size (#88).
Text {
  id: root

  property string label
  property bool accent: false
  signal triggered()

  text: root.label
  font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
  color: root.accent ? Theme.accentSoft : Theme.text3

  MouseArea {
    anchors.fill: parent
    // The text's own box is a few pixels tall; the margin is the hit target.
    anchors.margins: -4
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.triggered()
  }
}
