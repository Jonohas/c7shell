import QtQuick
import QtQuick.Effects
import qs.Theme

// 64×36 preview of the current wallpaper (2b). The rounded corners need a
// mask: Item.clip is a scissor rect and cannot round anything.
Item {
  id: root

  required property string path

  width: 64
  height: 36

  Image {
    id: pic
    anchors.fill: parent
    source: root.path !== "" ? `file://${root.path}` : ""
    fillMode: Image.PreserveAspectCrop
    sourceSize: Qt.size(128, 72)
    asynchronous: true
    visible: false
  }

  Rectangle {
    id: shape
    anchors.fill: parent
    radius: Theme.radiusThumb
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: parent
    source: pic
    maskEnabled: true
    maskSource: shape
    visible: pic.status === Image.Ready
  }

  // "img" placeholder while there is nothing to show, "?" if the path is bad.
  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusThumb
    color: Theme.surface07
    visible: pic.status !== Image.Ready

    Text {
      anchors.centerIn: parent
      text: pic.status === Image.Error ? "?" : "img"
      font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
      color: Theme.alpha(Theme.text, 0.4)
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusThumb
    color: "transparent"
    border.width: 1
    border.color: Theme.hairlineStrong
  }
}
