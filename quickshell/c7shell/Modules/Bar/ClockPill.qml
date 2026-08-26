import QtQuick
import qs.Theme
import qs.Services

Rectangle {
  id: root
  signal clicked()

  implicitWidth: content.implicitWidth + 28   // content tuning, not a token
  implicitHeight: Theme.pillHeight
  radius: Theme.pillRadius
  color: mouse.containsMouse ? Theme.surface07 : Theme.surface05

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 10

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: Time.dateLine
      font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
      color: Theme.alpha(Theme.text, 0.75)
    }
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 1; height: 12
      color: Theme.hairlineStrong
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: Time.hm
      font { family: Theme.fontMono; pixelSize: 12; weight: 700 }
      color: Theme.accentSoft
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.clicked()   // SP2 opens the calendar popover here
  }
}
