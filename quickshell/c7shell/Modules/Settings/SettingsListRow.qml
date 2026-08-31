import QtQuick
import qs.Theme

// The full-bleed row the topbar page's cards are built from: a title over a
// one-line explanation of what the setting actually does, and whatever control
// the setting needs on the right. Rows bleed to the card edge and separate
// themselves with a hairline, so the card reads as a list rather than as a
// stack of boxes.
//
// `indent` is for a row that only means anything while the row above it is on.
// Such rows are DISABLED rather than hidden -- a control that vanishes takes
// the explanation of what its parent toggle unlocks with it.
Item {
  id: root

  property string title: ""
  property string subtitle: ""
  property bool indent: false
  // The card draws no divider above its first row.
  property bool divider: true

  default property alias trailing: trailingSlot.data

  implicitHeight: Math.max(38, text.implicitHeight + 24)

  Rectangle {   // the indent wash: a hint of depth, not a second surface
    anchors.fill: parent
    visible: root.indent
    color: Qt.rgba(1, 1, 1, 0.015)
  }

  Rectangle {
    anchors { left: parent.left; right: parent.right; top: parent.top }
    visible: root.divider
    height: 1
    color: Theme.alpha(Theme.text, 0.05)
  }

  Column {
    id: text

    anchors {
      left: parent.left
      leftMargin: root.indent ? 30 : 14
      right: trailingSlot.left
      rightMargin: 14
      verticalCenter: parent.verticalCenter
    }
    spacing: 2
    // Greyed out, still readable: see the note at the top.
    opacity: root.enabled ? 1 : 0.45

    Text {
      width: parent.width
      text: root.title
      font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
      color: root.indent ? Theme.alpha(Theme.text, 0.8) : Theme.text
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: root.subtitle !== ""
      text: root.subtitle
      textFormat: Text.StyledText
      font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
      color: Theme.alpha(Theme.text, root.indent ? 0.35 : 0.38)
      wrapMode: Text.WordWrap
    }
  }

  Row {
    id: trailingSlot
    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
    spacing: 10
  }
}
