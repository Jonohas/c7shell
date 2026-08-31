import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Theme
import qs.Services
import qs.Modules.Capture
import qs.Modules.Updates

// The one top-right host: the capture card (5b) on top, the notification stack
// (1d) under it. There used to be two windows in this corner, each with its own
// idea of where the corner starts, and a screenshot taken while a notification
// was up drew the two cards on top of each other -- patched by publishing one
// window's bottom edge through a service property so the other could dodge it.
// One host, one Column, and the stacking is just layout.
PanelWindow {
  id: win

  // Room for each card's shadow to fade out inside the window. The right side
  // only ever gets the bar's own 12px margin, the same clipping the bar island
  // already lives with.
  readonly property int gutter: 30
  readonly property int cardWidth: 340

  // The capture card latches the monitor its capture happened on and must not
  // migrate; a notification belongs on the screen actually being used. While a
  // capture card is up its choice wins, since it is the shorter-lived one.
  screen: (capture.visible
    ? Quickshell.screens.find(s => s.name === capture.monitor)
    : null)
    ?? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
    ?? null

  // dnd is filtered at the source in NotifServer.onNotification, so anything
  // still in `popups` belongs on screen -- including the shell's own §8 failure
  // notices, which dnd deliberately does not silence.
  // Toasts are muted while sharing a screen; the notification still lands in
  // the popover list, only the on-screen pop-up is suppressed.
  readonly property bool anyNotif: NotifServer.popups.length > 0 && !ScreenshareService.active
  visible: win.anyNotif || capture.visible || updates.visible || power.visible

  anchors { top: true; right: true }
  // Ignore, not a zero zone: a zero zone still respects the bar's 48px, which
  // pushed the capture card 48px below where the mockup puts it. With the bar
  // measured here instead, the first card's top lands at screen y=60.
  exclusionMode: ExclusionMode.Ignore
  exclusiveZone: 0
  margins { top: Theme.barMarginTop + Theme.barHeight + 12; right: 0 }

  implicitWidth: win.cardWidth + Theme.barMarginSide + win.gutter
  implicitHeight: Math.max(1, stack.implicitHeight + win.gutter)
  color: "transparent"
  WlrLayershell.namespace: "c7shell-toasts"
  WlrLayershell.layer: WlrLayer.Overlay
  // Everything outside a card is dead space; without the mask the transparent
  // shadow gutter would eat clicks meant for the window underneath.
  mask: Region { item: stack }

  Column {
    id: stack

    anchors { top: parent.top; right: parent.right; rightMargin: Theme.barMarginSide }
    width: win.cardWidth
    spacing: 8

    FinishedToast {
      id: capture
      width: stack.width
    }

    // The end of a clean update run. Above the notification stack for the same
    // reason the capture card is: it is the shorter-lived of the two and it is
    // the thing you just asked for.
    UpdateToast {
      id: updates
      width: stack.width
    }

    // A profile the user did not pick by hand. Above the notification stack
    // for the same reason the two above it are: it is the shorter-lived one,
    // and it is about something that just happened to the machine.
    PowerToast {
      id: power
      width: stack.width
    }

    Repeater {
      model: NotifServer.popups

      Item {
        id: slot

        // modelData is a notification id, not the notification — see
        // NotifServer.popups for why the model must not hold objects.
        required property var modelData

        width: stack.width
        implicitHeight: card.implicitHeight
        visible: win.anyNotif && card.alive

        RectangularShadow {
          anchors.fill: card
          radius: card.radius
          color: Theme.panelShadowColor
          offset.y: 8
          blur: 24
          z: -1
        }

        NotifRow {
          id: card
          width: parent.width
          glass: true
          accented: true
          notificationId: slot.modelData
        }
      }
    }
  }
}
