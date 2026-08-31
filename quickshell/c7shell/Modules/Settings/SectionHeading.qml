import QtQuick
import qs.Theme

// The tracked-out caps label that names a group of cards on a settings page —
// LAYOUT, BATTERY, PREVIEW. The rule after it runs to the edge, so the eye has
// something to follow across a wide page.
Item {
  id: root

  required property string text
  // The first heading on a page has the page title above it and needs no rule
  // to separate it from anything.
  property bool rule: true

  implicitHeight: 12

  Text {
    id: label
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    text: root.text.toUpperCase()
    font {
      family: Theme.fontMono
      pixelSize: 9
      weight: 600
      letterSpacing: 0.9
    }
    color: Theme.alpha(Theme.text, 0.3)
  }

  Rectangle {
    anchors {
      left: label.right; leftMargin: 9
      right: parent.right
      verticalCenter: parent.verticalCenter
    }
    visible: root.rule
    height: 1
    color: Theme.hairline
  }
}
