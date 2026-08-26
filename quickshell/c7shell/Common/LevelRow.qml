import QtQuick
import qs.Theme
import qs.Services

// The 1g output/input line: mute glyph, "output · device", value. Drawn the
// same in the popover and on the settings page, so it lives here rather than
// once per view.
Item {
  id: root

  required property var node
  required property string prefix
  required property string icon

  readonly property bool muted: root.node?.audio?.muted ?? false

  implicitHeight: 14

  Icon {
    id: glyph
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    name: root.icon
    size: 13
    tint: root.muted ? Theme.accentSoft : Theme.alpha(Theme.text, 0.75)

    MouseArea {
      anchors.fill: parent
      anchors.margins: -3
      onClicked: AudioService.toggleMute(root.node)
    }
  }

  Text {
    anchors {
      left: glyph.right; leftMargin: 9
      right: value.left; rightMargin: 9
      verticalCenter: parent.verticalCenter
    }
    text: `${root.prefix} · ${AudioService.label(root.node)}` + (root.muted ? " · muted" : "")
    font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
    color: Theme.alpha(Theme.text, 0.8)
    elide: Text.ElideRight
  }

  Text {
    id: value
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    text: `${Math.round((root.node?.audio?.volume ?? 0) * 100)}`
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: Theme.alpha(Theme.text, 0.45)
  }
}
