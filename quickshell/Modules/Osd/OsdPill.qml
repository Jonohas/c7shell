import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.Theme
import qs.Common
import qs.Services

// The one OSD pill (spec §4a/4b): bottom-center glass, 320×44, every kind
// rendered in the same window so replacing one with another is a text change
// rather than a new surface. Per screen, but only the focused monitor's copy
// is ever mapped.
Scope {
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      readonly property string kind: OsdManager.kind
      readonly property var payload: OsdManager.payload
      readonly property int value: win.payload?.value ?? 0
      readonly property string hint: win.payload?.hint ?? ""
      // Crimson is reserved for "off": a muted sink or a muted mic.
      readonly property bool off: win.kind === "mute"
        || (win.kind === "mic" && (win.payload?.muted ?? false))
      readonly property bool slider: win.kind === "volume" || win.kind === "mute"
        || win.kind === "brightness"

      // modelData, not win.screen: a PanelWindow's `screen` is re-resolved when
      // the window is mapped, so reading it from a binding that also decides
      // `visible` is a loop the scene graph complains about every frame.
      readonly property bool onFocusedScreen: Hyprland.monitorFor(win.modelData)?.focused ?? false

      // Dot centers for a dice face, on a unit square -- the same layout the bar
      // pips use, so a workspace reads the same in both places.
      // ponytail: values 1-5 only; a higher workspace gets a plain tile and
      // leans on the label. Lift this into Common/ if a third caller shows up.
      function dots(n) {
        const lo = 0.30, mid = 0.50, hi = 0.70
        switch (n) {
          case 1: return [[mid, mid]]
          case 2: return [[lo, lo], [hi, hi]]
          case 3: return [[lo, lo], [mid, mid], [hi, hi]]
          case 4: return [[lo, lo], [hi, lo], [lo, hi], [hi, hi]]
          case 5: return [[lo, lo], [hi, lo], [mid, mid], [lo, hi], [hi, hi]]
          default: return []
        }
      }

      // Stays mapped through the fade-out, or the pill would vanish mid-animation.
      visible: win.onFocusedScreen && (OsdManager.showing || pill.opacity > 0)

      // Anchored to one edge only, so the compositor centers it. The window is
      // wider and taller than the pill to give `0 20px 60px` room to render.
      anchors.bottom: true
      implicitWidth: 400
      implicitHeight: 148
      exclusiveZone: 0
      color: "transparent"
      // The OSD is feedback, never a target: an empty mask makes the whole
      // window click-through.
      mask: Region {}
      WlrLayershell.namespace: "c7shell-osd"
      WlrLayershell.layer: WlrLayer.Overlay   // visible over fullscreen windows
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      GlassPanel {
        id: pill
        anchors {
          horizontalCenter: parent.horizontalCenter
          bottom: parent.bottom
          bottomMargin: 64
        }
        width: 320
        height: 44   // 13px padding + an 18px glyph + 13px
        radius: Theme.radiusPanel
        glassAlpha: Theme.glassAlphaBar   // mock 4a: rgba(15,15,19,.78)
        border.color: win.off ? Theme.accentBorder : Theme.hairlineStrong

        opacity: OsdManager.showing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Item {
          id: content
          anchors {
            fill: parent
            leftMargin: 18; rightMargin: 18
            topMargin: 13; bottomMargin: 13
          }

          Item {   // leading glyph: fixed box so the middle never shifts
            id: lead
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 18; height: 18

            Icon {
              anchors.centerIn: parent
              visible: win.kind !== "workspace"
              size: win.slider ? 18 : 17
              tint: win.off ? Theme.accentSoft : Theme.text
              name: {
                switch (win.kind) {
                  case "mute": return "volume-x"
                  case "brightness": return "sun"
                  case "mic": return win.off ? "mic-off" : "mic"
                  case "layout": return "keyboard"
                  // volume lands here, and so do workspace and the idle "" --
                  // both hide this Icon, and an empty name logs a load error.
                  default: return "volume-2"
                }
              }
            }

            Rectangle {   // workspace pip tile
              id: tile
              anchors.centerIn: parent
              visible: win.kind === "workspace"
              width: 17; height: 17
              radius: 6
              color: Theme.accent

              Repeater {
                model: win.dots(win.value)

                Rectangle {
                  required property var modelData
                  x: modelData[0] * tile.width - 1.5
                  y: modelData[1] * tile.height - 1.5
                  width: 3; height: 3; radius: 1.5
                  color: Theme.text
                }
              }
            }
          }

          Text {   // value, "mute", or the shortcut hint
            id: trail
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            // Fixed width for numbers so the track does not jump between 5 and 100.
            width: win.slider ? 28 : implicitWidth
            horizontalAlignment: Text.AlignRight
            text: {
              if (win.kind === "mute") return "mute"
              if (win.slider) return `${win.value}`
              return win.hint
            }
            color: win.kind === "mute" ? Theme.accentSoft
              : win.slider ? Theme.text : Theme.text3
            font {
              family: Theme.fontMono
              pixelSize: win.slider ? 12 : 10
              weight: win.slider ? 600 : 400
            }
          }

          Rectangle {   // 6px track -- feedback only, nothing drags it
            id: track
            visible: win.slider
            anchors {
              left: lead.right; leftMargin: 14
              right: trail.left; rightMargin: 14
              verticalCenter: parent.verticalCenter
            }
            height: 6
            radius: 3
            color: Theme.hairlineStrong

            Rectangle {
              // Muted is an empty track, and an overamplified sink stops at full.
              width: win.kind === "mute" ? 0
                : parent.width * Math.max(0, Math.min(1, win.value / 100))
              height: parent.height
              radius: parent.radius
              visible: width >= 1
              color: Theme.accent

              RectangularShadow {   // spec: slider fill glows 0 0 12px
                anchors.fill: parent
                radius: parent.radius
                color: Theme.accentGlow
                offset: Qt.vector2d(0, 0)
                blur: 12
                z: -1
              }
            }
          }

          Row {   // label side: mic / layout / workspace
            visible: !win.slider
            anchors {
              left: lead.right; leftMargin: 14
              right: trail.left; rightMargin: 14
              verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Text {
              text: {
                switch (win.kind) {
                  case "mic": return win.off ? "mic muted" : "mic on"
                  case "workspace": return `workspace ${win.value}`
                  case "layout": return "layout"
                  default: return ""
                }
              }
              font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
              color: Theme.text
            }
            Text {   // "us →", dimmed: the layout being left behind
              visible: win.kind === "layout"
              text: `${win.payload?.from ?? ""} →`
              font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
              color: Theme.text3
            }
            Text {
              visible: win.kind === "layout"
              text: win.payload?.to ?? ""
              font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
              color: Theme.text
            }
          }
        }
      }

      // Shadow only -- no source item to paint, so the pill stays translucent
      // and hyprland's blur has something to work on.
      RectangularShadow {
        anchors.fill: pill
        radius: pill.radius
        color: Theme.panelShadowColor
        offset.y: 20
        blur: 60
        opacity: pill.opacity
        z: -1
      }
    }
  }
}
