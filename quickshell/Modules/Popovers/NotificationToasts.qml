import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Theme
import qs.Services

// The toast stack, top-right under the bar, on whichever monitor has focus — a
// notification should land on the screen actually being used. Suppressed
// wholesale while do-not-disturb is on; the list in 1d still gets everything.
PanelWindow {
  id: win

  // Room for each card's shadow to fade out inside the window. The right side
  // only ever gets the bar's own 12px margin, the same clipping the bar island
  // already lives with.
  readonly property int gutter: 30
  readonly property int cardWidth: 340

  screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

  // dnd is filtered at the source in NotifServer.onNotification, so anything
  // still in `popups` belongs on screen -- including the shell's own §8 failure
  // notices, which dnd deliberately does not silence.
  // Toasts are muted while sharing a screen; the notification still lands in
  // the popover list, only the on-screen pop-up is suppressed.
  visible: NotifServer.popups.length > 0 && !ScreenshareService.active

  anchors { top: true; right: true }
  // The bar's exclusive zone already pushes this down, so the top margin is the
  // gap below the bar rather than the distance from the screen edge.
  //
  // The capture toast claims the same slot -- its card lands at screen y=60,
  // this stack starts at 56 -- so a screenshot taken while a notification was up
  // drew the two on top of each other. Yield to it: it is the shorter-lived card
  // and the one the user just asked for. This window sits below the bar's
  // exclusive zone, the capture toast ignores it, so its published edge has to
  // be brought back into this frame.
  // ponytail: two hosts is the real defect -- one top-right host with two card
  // types (simplify pass S5) deletes this coupling along with ~60 lines.
  readonly property int barZone: Theme.barMarginTop + Theme.barHeight
  margins {
    top: Math.max(8, CaptureService.toastBottom > 0
      ? CaptureService.toastBottom + 8 - win.barZone
      : 8)
    right: 0
  }

  implicitWidth: win.cardWidth + Theme.barMarginSide + win.gutter
  implicitHeight: Math.max(1, stack.implicitHeight + win.gutter)
  color: "transparent"
  WlrLayershell.namespace: "c7shell-toasts"

  // Claim no space of its own, or the toasts would shove windows around.
  exclusiveZone: 0
  // Everything outside a card is dead space; without the mask the transparent
  // shadow gutter would eat clicks meant for the window underneath.
  mask: Region { item: stack }

  Column {
    id: stack

    anchors { top: parent.top; right: parent.right; rightMargin: Theme.barMarginSide }
    width: win.cardWidth
    spacing: 8

    Repeater {
      model: NotifServer.popups

      Item {
        id: slot

        // modelData is a notification id, not the notification — see
        // NotifServer.popups for why the model must not hold objects.
        required property var modelData

        width: stack.width
        implicitHeight: card.implicitHeight
        visible: card.alive

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
