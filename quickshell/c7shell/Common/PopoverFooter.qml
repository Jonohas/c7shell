import QtQuick
import qs.Theme

// The hairline-topped action strip at the bottom of 1e/1f/1g: a rescan-style
// action on the left, a crimson route into the settings app on the right.
Item {
  id: root

  property string leftIcon: ""
  property string leftText: ""
  property string rightText: ""

  signal leftClicked()
  signal rightClicked()

  implicitHeight: 11 + Math.max(left.implicitHeight, right.implicitHeight)

  Rectangle {
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: 1
    color: Theme.hairline
  }

  Row {
    id: left

    anchors { left: parent.left; bottom: parent.bottom }
    spacing: 5
    visible: root.leftText !== ""
    opacity: leftMouse.containsMouse ? 1 : 0.75

    // Loader, not a hidden Icon: an Icon with an empty name still resolves
    // ".../.svg" and logs a load failure the integrator's warning count sees.
    Loader {
      anchors.verticalCenter: parent.verticalCenter
      active: root.leftIcon !== ""
      sourceComponent: Icon {
        name: root.leftIcon
        size: 11
        tint: Theme.alpha(Theme.text, 0.45)
      }
    }
    Text {
      text: root.leftText
      font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
      color: Theme.alpha(Theme.text, 0.45)
    }
  }

  // Sibling, not a Row child: positioners flow-place their children, so an
  // anchors.fill child inside the Row both warns and breaks the layout.
  MouseArea {
    id: leftMouse
    anchors.fill: left
    anchors.margins: -4
    hoverEnabled: true
    onClicked: root.leftClicked()
  }

  Text {
    id: right

    anchors { right: parent.right; bottom: parent.bottom }
    text: root.rightText
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: Theme.accentSoft
    opacity: rightMouse.containsMouse ? 1 : 0.85

    MouseArea {
      id: rightMouse
      anchors.fill: parent
      anchors.margins: -4
      hoverEnabled: true
      onClicked: root.rightClicked()
    }
  }
}
