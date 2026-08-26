import QtQuick
import qs.Theme

// Static key legend along the bottom of the command window.
Item {
  height: 33

  Row {
    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
    spacing: 14

    Repeater {
      model: ["↑↓ move", "↵ open", "ctrl+↵ terminal", "= calc inline"]
      Text {
        required property string modelData
        text: modelData
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: Theme.alpha(Theme.text, 0.35)
      }
    }
  }

  Row {
    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
    spacing: 5

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 6; height: 6; radius: 2
      color: Theme.accent
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "gambleland"
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.35)
    }
  }
}
