import QtQuick
import qs.Theme
import qs.Common

// The label-and-toggle line the 2a/2b cards end on ("route all traffic through
// active vpn", "window opacity on inactive").
Item {
  id: root

  required property string label
  required property bool checked

  signal toggled()

  implicitHeight: 17

  Text {
    anchors {
      left: parent.left
      right: pill.left; rightMargin: 10
      verticalCenter: parent.verticalCenter
    }
    text: root.label
    font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
    color: Theme.alpha(Theme.text, 0.5)
    elide: Text.ElideRight
  }

  TogglePill {
    id: pill
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    checked: root.checked
    onToggled: root.toggled()
  }
}
