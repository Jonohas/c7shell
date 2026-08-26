import QtQuick
import Quickshell
import qs.Theme
import qs.Common

// The 180px glass menu that drops out of an open top-level menu label.
// Anchor arithmetic and the item list only -- the window, its grab, its mask
// and its shadow are PopupSurface's.
//
// Keys are handled on the bar, not here: the grab covers the bar too and
// Hyprland keeps the keyboard on that surface. See GlobalMenuSlot.
PopupSurface {
  id: popup

  property var items: []

  signal itemActivated(var item)

  // Gutter around the panel so the drop shadow has somewhere to land, sized to
  // the shadow (offset 10, blur 28) rather than square: the tail falls
  // downwards, and a wide left gutter would push the anchor rect off the front
  // of the bar. The anchor rect subtracts the gutter again, so the PANEL -- not
  // the window -- ends up 6px under the label.
  gutterX: 30
  gutterTop: 10
  gutterBottom: 50
  panelWidth: 180
  panelHeight: rows.implicitHeight + 10   // 5px panel padding, top and bottom
  panelRadius: Theme.radiusMenu
  shadowOffset: 10
  shadowBlur: 28
  // A menu bar switches menus faster than a 150ms fade can follow.
  fade: false

  anchor {
    // 1x1 anchor rect at the label's bottom-left, shifted up/left by the
    // gutter. -1 on y compensates for the rect's own height.
    rect.x: -popup.gutterX
    rect.y: (popup.lastAnchor?.height ?? 0) + 5 - popup.gutterTop
    rect.width: 1
    rect.height: 1
    edges: Edges.Bottom | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    // Slide back on screen near the right edge; never flip above the bar.
    adjustment: PopupAdjustment.SlideX
  }

  Column {
    id: rows
    x: 5
    y: 5
    width: parent.width - 10

    Repeater {
      model: popup.items

      Rectangle {
        id: row
        required property var modelData
        required property int index

        readonly property bool clickable: !row.modelData.separator && row.modelData.enabled !== false
        readonly property bool selected: row.clickable && mouse.containsMouse

        width: rows.width
        height: row.modelData.separator ? 9 : 24
        radius: Theme.radiusMenuRow
        color: row.selected ? Theme.alpha(Theme.accent, 0.85) : "transparent"

        Rectangle {
          anchors.centerIn: parent
          width: parent.width - 12
          height: 1
          color: Theme.hairline
          visible: row.modelData.separator === true
        }

        Text {
          // Ends at the shortcut, never under it: at 180px "Private Window"
          // and its ctrl+shift+p overlapped.
          anchors {
            left: parent.left; leftMargin: 9
            right: shortcut.left; rightMargin: 8
            verticalCenter: parent.verticalCenter
          }
          visible: !row.modelData.separator
          text: row.modelData.label ?? ""
          font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
          color: !row.clickable ? Theme.textDisabled
            : row.selected ? Theme.text : Theme.alpha(Theme.text, 0.8)
          elide: Text.ElideRight
        }

        Text {
          id: shortcut
          anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
          visible: !row.modelData.separator
          text: row.modelData.shortcut ?? ""
          font { family: Theme.fontMono; pixelSize: 10 }
          color: row.selected ? Theme.alpha(Theme.text, 0.7) : Theme.text3
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          enabled: row.clickable
          hoverEnabled: true
          onClicked: popup.itemActivated(row.modelData)
        }
      }
    }
  }
}
