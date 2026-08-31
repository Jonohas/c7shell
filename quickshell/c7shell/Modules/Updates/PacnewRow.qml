import QtQuick
import qs.Theme
import qs.Services

// One config file pacman could not overwrite, with the three things you can do
// about it.
//
// Amber, not crimson: nothing here failed. A .pacnew is housekeeping, and
// colouring it like an error is what trains people to ignore the colour.
Rectangle {
  id: root

  required property var file          // { path, changed, edited }


  implicitWidth: parent ? parent.width : 340
  implicitHeight: body.implicitHeight + 18
  radius: Theme.radiusRow
  color: Theme.surface04
  border.width: 1
  border.color: Theme.hairline

  Column {
    id: body
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
    spacing: 6

    Row {
      width: parent.width
      spacing: 5

      Text {
        text: root.file.path
        font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
        color: Theme.text
      }
      Text {
        text: ".pacnew"
        font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
        color: Theme.warning
      }
    }

    Text {
      width: parent.width
      elide: Text.ElideRight
      // pacman records whether you edited a backup file, so this is a fact
      // rather than a guess -- and it is the whole difference between "read
      // this diff carefully" and "just take the new one".
      text: root.file.edited
        ? `${root.file.changed} changed line${root.file.changed === 1 ? "" : "s"} · you edited this file`
        : `${root.file.changed} changed line${root.file.changed === 1 ? "" : "s"} · default untouched → safe to take new`
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3
    }

    Row {
      spacing: 6

      Choice { label: "keep mine"; onTriggered: UpdatesService.resolvePacnew("keep", root.file.path) }
      Choice {
        label: "take new"
        // Highlighted only where it is actually the safe answer.
        highlight: !root.file.edited
        onTriggered: UpdatesService.resolvePacnew("take", root.file.path)
      }
      // A three-pane merge is an editor, and an editor is a terminal's job.
      Choice { label: "merge…"; onTriggered: UpdatesService.mergePacnew(root.file.path) }
    }
  }

  component Choice: Rectangle {
    id: choice
    property string label
    property bool highlight: false
    signal triggered()

    implicitWidth: text.implicitWidth + 16
    implicitHeight: 21
    radius: Theme.radiusChip
    color: choiceHover.hovered ? Theme.surface07 : Theme.surface04
    border.width: 1
    border.color: choice.highlight ? Theme.alpha(Theme.warning, 0.4) : Theme.hairline

    Text {
      id: text
      anchors.centerIn: parent
      text: choice.label
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: choice.highlight ? Theme.warning : Theme.text2
    }

    HoverHandler { id: choiceHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: choice.triggered() }
  }
}
