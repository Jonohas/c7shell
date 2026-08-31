import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import qs.Theme
import qs.Common
import qs.Services

Scope {
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      anchors { top: true; left: true; right: true }
      // Extra height so the island's drop shadow has room to render: offset 12
      // plus the blur tail, measured to reach the desktop again 36px below the
      // island. Raise this with `blur` or `offset.y` or the tail cuts off square.
      implicitHeight: Theme.barMarginTop + Theme.barHeight + 36
      exclusiveZone: Theme.barMarginTop + Theme.barHeight
      color: "transparent"
      WlrLayershell.namespace: "c7shell-bar"
      // OnDemand, for the popovers rather than for the bar itself: a popover is
      // an xdg-popup of this surface, and the keyboard grab one takes when a
      // text field inside it is focused (the wifi row's password) is REFUSED if
      // the parent surface is not keyboard-interactive -- measured, esc and
      // every keystroke then stop reaching the panel. Focus still only lands
      // here on click, so the bar never steals the keyboard at idle.
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

      // "islands": the bar surface goes transparent and each cluster gets its
      // own pill behind it instead. Deliberately NOT a second layout -- the
      // clusters, their anchors and their popover arithmetic are identical
      // either way, so the two modes differ only in what is painted.
      readonly property bool islands: ShellStore.islandStyle === "islands"

      // Only the island takes pointer input; without this the whole window --
      // including the transparent shadow gutter -- would eat clicks meant for
      // the windows below. The island keeps its geometry in islands mode, so
      // it stays the mask there too: the gaps between the pills are part of the
      // bar's strip either way, exactly as they were when it was one surface.
      mask: Region { item: island }

      GlassPanel {
        id: island
        anchors {
          top: parent.top; topMargin: Theme.barMarginTop
          left: parent.left; leftMargin: Theme.barMarginSide
          right: parent.right; rightMargin: Theme.barMarginSide
        }
        height: Theme.barHeight
        radius: Theme.radiusBar
        glassAlpha: Theme.glassAlphaBar
        // The surface is the only thing islands mode removes; the item stays,
        // because all three clusters and the shadow still measure off it.
        color: win.islands ? "transparent" : Theme.alpha(Theme.glassBase, glassAlpha)
        border.width: win.islands ? 0 : 1

        // The per-cluster pills. Drawn behind the clusters rather than wrapped
        // around them so that nothing about the clusters themselves changes:
        // a widget that is hidden collapses its Row exactly as before, and the
        // pill behind it follows.
        Repeater {
          model: win.islands ? [leftCluster, centerCluster, rightCluster] : []

          GlassPanel {
            required property var modelData

            // A cluster with nothing in it -- an empty tray, a hidden menu slot
            // -- gets no pill rather than an empty crumb of glass.
            visible: modelData.width > 0
            x: modelData.x - 8
            // Repeater parents the delegate to the island itself.
            y: (parent.height - height) / 2
            width: modelData.width + 16
            height: Theme.pillHeight + 6
            radius: height / 2
            glassAlpha: Theme.glassAlphaBar
            z: -1
          }
        }

        // A popover's focus grab covers this window as well, so that a click on
        // another bar module switches popovers in one click instead of closing
        // the first one -- but Hyprland then keeps the keyboard on THIS surface.
        // Hand it back to whatever holds focus inside the open popover: esc, and
        // the wi-fi row's password field. Keys the menu slot has already
        // accepted never get here.
        Keys.forwardTo: PopoverManager.keySink ? [PopoverManager.keySink] : []

        Row {
          id: leftCluster
          anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
          spacing: 10

          // Pass this window's own monitor down: workspace focus is per-monitor.
          WorkspacePips {
            anchors.verticalCenter: parent.verticalCenter
            monitor: Hyprland.monitorFor(win.screen)
          }
          GlobalMenuSlot { anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, 420) }
        }

        Item {
          id: centerCluster
          anchors.centerIn: parent
          height: parent.height
          // Was zero-width: the children centre themselves inside it and
          // nothing ever measured it. The islands-mode pill behind it does, so
          // it now takes the width of whichever child is actually showing.
          width: RecordingService.active ? rec.width : clock.width

          ClockPill {
            id: clock
            anchors.centerIn: parent
            visible: !RecordingService.active
            onClicked: PopoverManager.toggle("calendar", clock)
          }
          RecordingIsland {
            id: rec
            anchors.centerIn: parent
            visible: RecordingService.active
          }
        }

        Row {
          id: rightCluster
          anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
          spacing: 8

          TrayPill { anchors.verticalCenter: parent.verticalCenter }
          StatusPill { anchors.verticalCenter: parent.verticalCenter }
          PowerButton {
            id: powerBtn
            anchors.verticalCenter: parent.verticalCenter
            onClicked: PopoverManager.toggle("power", powerBtn)
          }
        }
      }

      // Shadow only - no source item to paint, so the island above it stays
      // translucent and Hyprland's blur has something to work on.
      RectangularShadow {
        anchors.fill: island
        // In islands mode there is no bar to cast one, and a shadow the shape
        // of the invisible container would look like a bug.
        visible: !win.islands
        radius: island.radius
        color: Theme.barShadowColor
        offset.y: 12
        blur: 40
        z: -1
      }
    }
  }
}
