import QtQuick
import qs.Theme
import qs.Common

Rectangle {
  id: root
  signal clicked()

  width: 28; height: 28; radius: 14
  color: mouse.containsMouse ? Theme.powerHover : Theme.accentFill
  border.width: 1
  border.color: Theme.accentBorder

  Icon {
    // Even size: 13px in a 28px circle centers on a half pixel and blurs.
    anchors.centerIn: parent
    name: "power"
    size: 14
    tint: Theme.accentSoft
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.clicked()   // SP5 opens PowerDropdown here
  }
}
