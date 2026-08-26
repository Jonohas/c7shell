import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import qs.Theme
import qs.Common

// The 180px glass menu that drops out of an open top-level menu label.
// Positioning, input grab and key handling only -- the item list is handed in.
PopupWindow {
  id: popup

  property Item anchorItem: null
  property var items: []

  // Keys are handled on the bar, not here: the grab below covers the bar too and
  // Hyprland keeps the keyboard on that surface. See GlobalMenuSlot.
  signal closeRequested
  signal itemActivated(var item)

  // Gutter around the panel so the drop shadow has somewhere to land, sized to
  // the shadow below (offset 10, blur 28) rather than square: the tail falls
  // downwards, and a wide left gutter would push the anchor rect off the front
  // of the bar. The anchor rect subtracts the gutter again, so the PANEL -- not
  // the window -- ends up 6px under the label.
  readonly property int padSide: 30
  readonly property int padTop: 10
  readonly property int padBottom: 50
  readonly property int menuWidth: 180

  color: "transparent"
  visible: false
  // Hyprland's focus grab does this instead; an xdg-popup grab on a layer
  // surface that is not keyboard-interactive gets refused.
  grabFocus: false

  implicitWidth: popup.menuWidth + popup.padSide * 2
  implicitHeight: panel.height + popup.padTop + popup.padBottom
  // Only the menu takes pointer input; without this the transparent gutter
  // would swallow clicks meant for the bar and the windows below it.
  mask: Region { item: panel }

  anchor {
    item: popup.anchorItem
    // 1x1 anchor rect at the label's bottom-left, shifted up/left by the
    // gutter. -1 on y compensates for the rect's own height.
    rect.x: -popup.padSide
    rect.y: (popup.anchorItem?.height ?? 0) + 5 - popup.padTop
    rect.width: 1
    rect.height: 1
    edges: Edges.Bottom | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    // Slide back on screen near the right edge; never flip above the bar.
    adjustment: PopupAdjustment.SlideX
  }

  // The grab has to be requested a frame AFTER the surface is mapped or the
  // compositor refuses it and `active` silently stays false -- see
  // _archive/PopupPanel.qml.
  HyprlandFocusGrab {
    id: grab
    // The bar has to be inside the grab as well. The menu labels live on the
    // bar's surface, not this popup's, so a grab over the popup alone would
    // treat the click that means "switch to Edit" as an outside click and
    // close the menu instead.
    windows: popup.anchorItem ? [popup, popup.anchorItem.QsWindow.window] : [popup]
    onCleared: popup.closeRequested()
  }

  Timer {
    interval: 1
    running: popup.visible
    onTriggered: grab.active = true
  }

  onVisibleChanged: if (!popup.visible) grab.active = false

  RectangularShadow {
    anchors.fill: panel
    radius: panel.radius
    color: Theme.panelShadowColor
    offset.y: 10
    blur: 28
    z: -1
  }

  GlassPanel {
    id: panel
    x: popup.padSide
    y: popup.padTop
    width: popup.menuWidth
    height: rows.implicitHeight + 10   // 5px panel padding, top and bottom
    radius: Theme.radiusMenu

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
}
