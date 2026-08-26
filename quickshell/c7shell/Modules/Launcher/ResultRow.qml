import QtQuick
import Quickshell
import qs.Theme
import qs.Common

// One command-window result. `entry` is a plain JS row from a provider:
// { title, sub, meta, mono, icon? }.
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

  // App and window rows carry an icon *name*; action, calc and file rows have
  // none and keep their monogram. Resolved here rather than in the providers so
  // there is one lookup site, and `check: true` turns a name the icon theme
  // does not have into "", which falls back to the tile instead of drawing
  // Qt's broken-image box.
  readonly property string iconSource: row.entry?.icon
    ? Quickshell.iconPath(row.entry.icon, true) : ""

  MonogramTile {
    id: tile
    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
    size: 32
    radius: Theme.radiusTile
    glyph: row.entry?.mono ?? ""
    accented: row.selected
    visible: row.iconSource === ""
  }

  // App icons are already coloured, so unlike the Icon glyphs they are not
  // tinted -- same call as TrayPill's tray icons. 28 inside the 32 tile slot:
  // full-bleed icons keep roughly the monogram's visual weight in a mixed list.
  Image {
    anchors.centerIn: tile
    width: 28
    height: 28
    visible: row.iconSource !== ""
    source: row.iconSource
    sourceSize: Qt.size(56, 56)  // 2x, downscaled so it stays crisp
    asynchronous: true
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
