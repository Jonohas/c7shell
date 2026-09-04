import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.Theme
import qs.Common
import qs.Services

// The seconds the toolbar's "3s" chip buys you, drawn while the overlay is
// down -- and it has to be down, or grim would photograph the dim and the
// toolbar instead of the screen you are arranging.
//
// Without this the delay was three seconds of nothing: no number, no shutter,
// nothing to tell the chip from a no-op. The failure that made it worse was
// the obvious reaction to that silence -- pressing the keybind again to
// "retry" reopens the overlay, and reopening cancels the shot that was still
// coming.
//
// The pill is a layer surface like the overlay, so it unmaps the instant the
// count reaches zero and CaptureOverlay's recomposite grace covers both.
Scope {
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      // The output the capture was armed on, latched by the service when the
      // countdown started -- not the focused one, which follows the pointer
      // and would hop the pill between screens mid-count.
      visible: CaptureService.countdown > 0
        && CaptureService.countdownMonitor === win.modelData.name

      // Where the toolbar just was: the number takes over the spot the
      // "capture" button was pressed in rather than appearing somewhere new.
      anchors.bottom: true
      implicitWidth: 400
      implicitHeight: 120   // room for the panel shadow to render
      exclusiveZone: 0
      color: "transparent"
      // Feedback, never a target: an empty mask makes the whole window
      // click-through, so the seconds can be spent on the windows underneath
      // it. That is also why it takes no keyboard focus -- and therefore why
      // esc does not cancel here. Reopening the overlay does.
      mask: Region {}
      WlrLayershell.namespace: "c7shell-capture-countdown"
      WlrLayershell.layer: WlrLayer.Overlay   // over fullscreen windows
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      GlassPanel {
        id: pill
        anchors {
          horizontalCenter: parent.horizontalCenter
          bottom: parent.bottom
          bottomMargin: 18
        }
        width: row.implicitWidth + 28
        height: row.implicitHeight + 16
        radius: Theme.radiusPanel
        glassAlpha: Theme.glassAlphaPanel

        RectangularShadow {
          anchors.fill: parent
          radius: pill.radius
          color: Theme.panelShadowColor
          offset.y: 16
          blur: 40
          z: -1
        }

        Row {
          id: row
          anchors.centerIn: parent
          spacing: 9

          Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "timer"
            size: 13
            tint: Theme.accentSoft
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: `capturing in ${CaptureService.countdown}`
            font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
            color: Theme.text
          }
        }
      }
    }
  }
}
