pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common

// One of pacman / aur / flatpak, collapsed to `pac  pacman  12  ▸` and
// expanding to every package in it as old → new.
//
// Collapsed by default on the escalated path and open on the clean one: when
// nothing needs deciding the list *is* the content, and when something does
// the decisions are, so the list gets out of their way.
Rectangle {
  id: root

  required property var source          // { key, label, items[] }
  property bool expanded: false
  // How many rows before "show N more". The mock stops at six.
  readonly property int visibleRows: 6
  property bool showAll: false

  readonly property var items: root.source?.items ?? []
  readonly property int count: root.items.length

  visible: root.count > 0
  implicitWidth: parent ? parent.width : 300
  implicitHeight: body.implicitHeight + 16
  radius: Theme.radiusRow
  color: Theme.surface04
  border.width: 1
  border.color: Theme.hairline

  Column {
    id: body
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
    spacing: 7

    Item {   // header
      width: parent.width
      height: 16

      Rectangle {   // the three-letter source tag
        id: tag
        anchors.verticalCenter: parent.verticalCenter
        width: 26; height: 15
        radius: 4
        color: Theme.surface07

        Text {
          anchors.centerIn: parent
          text: root.source?.key === "flatpak" ? "fp" : root.source?.key === "aur" ? "aur" : "pac"
          font { family: Theme.fontMono; pixelSize: 8.5; weight: 600 }
          color: Theme.text3
        }
      }

      Text {
        anchors { left: tag.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
        text: root.source?.label ?? ""
        font { family: Theme.fontMono; pixelSize: 10.5; weight: 500 }
        color: Theme.text
      }

      Text {
        anchors { right: chevron.left; rightMargin: 7; verticalCenter: parent.verticalCenter }
        text: `${root.count}`
        font { family: Theme.fontMono; pixelSize: 10.5; weight: 600 }
        color: Theme.text2
      }

      Text {
        id: chevron
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: root.expanded ? "▾" : "▸"
        font { family: Theme.fontMono; pixelSize: 9 }
        color: Theme.text3
      }

      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: root.expanded = !root.expanded }
    }

    Column {
      width: parent.width
      spacing: 4
      visible: root.expanded

      Repeater {
        model: root.showAll ? root.items : root.items.slice(0, root.visibleRows)

        Item {
          id: row
          required property var modelData
          width: parent.width
          height: 13

          Text {
            anchors.left: parent.left
            width: Math.min(implicitWidth, parent.width * 0.5)
            elide: Text.ElideRight
            text: row.modelData.name
            font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
            color: Theme.text2
          }
          VersionDelta {
            anchors.right: parent.right
            oldVersion: row.modelData.old ?? ""
            newVersion: row.modelData.new ?? ""
          }
        }
      }

      Text {
        visible: !root.showAll && root.count > root.visibleRows
        text: `show ${root.count - root.visibleRows} more ▾`
        font { family: Theme.fontMono; pixelSize: 9.5; weight: 400 }
        color: Theme.text3

        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.showAll = true }
      }
    }
  }
}
