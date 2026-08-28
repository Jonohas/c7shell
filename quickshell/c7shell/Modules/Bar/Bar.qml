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
      // Only the island takes pointer input; without this the whole window --
      // including the transparent shadow gutter -- would eat clicks meant for
      // the windows below.
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

          // 15b: immediately left of the tray. It hides itself when nothing is
          // registered on MPRIS, and Row drops an invisible child's spacing
          // with it, so the bar closes up rather than holding the gap.
          MediaPill {
            id: media
            anchors.verticalCenter: parent.verticalCenter
            open: PopoverManager.current === "media"
            onClicked: PopoverManager.toggle("media", media)
          }
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
        radius: island.radius
        color: Theme.barShadowColor
        offset.y: 12
        blur: 40
        z: -1
      }
    }
  }
}
