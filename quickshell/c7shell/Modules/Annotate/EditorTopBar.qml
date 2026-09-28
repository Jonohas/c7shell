import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// Mockup 9a's two top corners: what is being edited on the left, what can be
// done with it on the right.
Item {
  id: top

  implicitHeight: Math.max(left.implicitHeight, right.implicitHeight)

  Row {
    id: left
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    spacing: 10

    GlassPanel {
      anchors.verticalCenter: parent.verticalCenter
      implicitWidth: name.implicitWidth + 20
      implicitHeight: name.implicitHeight + 12
      radius: Theme.radiusChip
      glassAlpha: Theme.glassAlphaPanel

      Text {
        id: name
        anchors.centerIn: parent
        text: AnnotateService.source.substring(AnnotateService.source.lastIndexOf("/") + 1)
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        color: Theme.text
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      // The size the EXPORT will be, so a crop is visible here the moment it
      // is made rather than after the file has been written.
      text: {
        const size = `${AnnotateService.frameWidth} × ${AnnotateService.frameHeight}`
        return AnnotateService.edited ? `${size} · edited` : size
      }
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3
    }
  }

  Row {
    id: right
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    spacing: 6

    Action {
      label: "undo"
      // Dimmed rather than hidden: a control that vanishes when there is
      // nothing to undo moves the two beside it under the pointer.
      enabled: AnnotateService.canUndo
      onClicked: AnnotateService.undo()
    }
    Action {
      label: "redo"
      enabled: AnnotateService.canRedo
      onClicked: AnnotateService.redo()
    }
    Action {
      label: "copy ↵"
      primary: true
      onClicked: AnnotateService.apply()
    }
  }

  component Action: Rectangle {
    id: action

    property string label
    property bool primary: false
    signal clicked()

    anchors.verticalCenter: parent.verticalCenter
    width: actionText.implicitWidth + 26
    height: 26
    radius: Theme.radiusChip
    color: action.primary ? Theme.accent
      : Theme.alpha(Theme.glassBase, Theme.glassAlphaPanel)
    border.width: action.primary ? 0 : 1
    border.color: Theme.hairline
    // The design's 30%: still legible as a word, plainly not a button.
    opacity: action.enabled ? 1 : 0.3

    Text {
      id: actionText
      anchors.centerIn: parent
      text: action.label
      font { family: Theme.fontMono; pixelSize: 10; weight: action.primary ? 600 : 500 }
      color: action.primary ? Theme.textOnAccent : Theme.text2
    }

    MouseArea {
      anchors.fill: parent
      enabled: action.enabled
      onClicked: action.clicked()
    }
  }
}
