import QtQuick
import qs.Theme
import qs.Common

// One command-window result. `entry` is a plain JS row from a provider:
// { title, sub, meta, mono }.
Rectangle {
  id: row

  property var entry
  property bool selected: false

  signal activated()
  signal hovered()

  implicitHeight: 50
  radius: Theme.radiusRow
  color: row.selected ? Theme.accentFill : "transparent"
  border.width: 1
  border.color: row.selected ? Theme.accentBorder : "transparent"

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onEntered: row.hovered()
    onClicked: row.activated()
  }

  MonogramTile {
    id: tile
    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
    size: 32
    radius: Theme.radiusTile
    glyph: row.entry?.mono ?? ""
    accented: row.selected
  }

  Column {
    anchors {
      left: tile.right; leftMargin: 12
      right: meta.left; rightMargin: 10
      verticalCenter: parent.verticalCenter
    }
    spacing: 2

    Text {
      width: parent.width
      elide: Text.ElideRight
      text: row.entry?.title ?? ""
      font { family: Theme.fontMono; pixelSize: 13; weight: row.selected ? 600 : 500 }
      color: row.selected ? Theme.text : Theme.alpha(Theme.text, 0.85)
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: row.entry?.sub ?? ""
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3
    }
  }

  // Selected rows advertise ↵; the rest show their own verb (run / jump / …).
  Item {
    id: meta
    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
    width: row.selected ? enterChip.implicitWidth : verb.implicitWidth
    height: row.selected ? enterChip.implicitHeight : verb.implicitHeight

    KbdChip {
      id: enterChip
      anchors.centerIn: parent
      visible: row.selected
      text: "↵"
      accent: true
      hPadding: 8
    }
    Text {
      id: verb
      anchors.centerIn: parent
      visible: !row.selected
      text: row.entry?.meta ?? ""
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.3)
    }
  }
}
