import QtQuick
import qs.Theme
import qs.Common

// One application in the 1g mixer: monogram tile, name, 4px track, value —
// or ✕ and the whole row at .45 once it is muted.
Item {
  id: root

  required property var node

  readonly property bool muted: root.node?.audio?.muted ?? false
  readonly property string appLabel: root.node
    ? `${root.node.properties["application.name"] || root.node.name}`.toLowerCase()
    : ""

  implicitHeight: 24
  opacity: root.muted ? 0.45 : 1

  MonogramTile {
    id: tile
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    size: 24
    label: root.appLabel
  }

  Column {
    anchors {
      left: tile.right; leftMargin: 10
      right: value.left; rightMargin: 10
      verticalCenter: parent.verticalCenter
    }
    spacing: 4

    Text {
      width: parent.width
      text: root.muted ? `${root.appLabel} · muted` : root.appLabel
      font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
      color: Theme.alpha(Theme.text, 0.7)
      elide: Text.ElideRight
    }

    CrimsonSlider {
      width: parent.width
      thumb: false
      trackHeight: 4
      fillColor: Theme.alpha(Theme.accent, 0.8)
      value: root.muted ? 0 : (root.node?.audio?.volume ?? 0)
      onMoved: v => {
        if (!root.node?.audio) return
        root.node.audio.muted = false
        root.node.audio.volume = v
      }
    }
  }

  Text {
    id: value

    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    text: root.muted ? "✕" : `${Math.round((root.node?.audio?.volume ?? 0) * 100)}`
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: Theme.alpha(Theme.text, 0.4)

    MouseArea {
      anchors.fill: parent
      anchors.margins: -4
      onClicked: if (root.node?.audio) root.node.audio.muted = !root.node.audio.muted
    }
  }
}
