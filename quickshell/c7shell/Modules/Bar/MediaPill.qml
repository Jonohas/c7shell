import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// Design 15b, topbar pill: art tile · four crimson bars · title. Sits left of
// TrayPill. Standard pill vocabulary, so it reads as one of the family with
// ClockPill and StatusPill rather than as a widget bolted on.
//
// Collapsed entirely when no player is registered -- `visible: false` on a Row
// child drops its spacing too, so the bar loses the gap as well as the pill.
// Anything less leaves a hole in the bar on a machine playing nothing, which is
// most machines most of the time.
Rectangle {
  id: root
  signal clicked()

  // Named to match QuickSlot rather than a popover's own `open`: this is the
  // pill's highlight, not MediaPopover's identity.
  property bool active: false

  visible: MprisService.hasPlayer

  implicitWidth: content.implicitWidth + 12   // content tuning, not a token
  implicitHeight: Theme.pillHeight
  radius: Theme.pillRadius
  color: root.active ? Theme.accentFillActive
    : mouse.containsMouse ? Theme.hoverPill
    : Theme.surface05
  Behavior on color { ColorAnimation { duration: 120 } }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 8

    // 22px art tile, r6. The placeholder is not a fallback for a slow load --
    // it is what most players show most of the time, so it is drawn underneath
    // rather than swapped in.
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 22; height: 22
      radius: 6
      color: Theme.surface07
      border.width: 1
      border.color: Theme.hairline
      clip: true

      Icon {
        anchors.centerIn: parent
        name: "music"
        size: 11
        tint: Theme.text3
      }

      Image {
        anchors.fill: parent
        source: MprisService.artUrl
        fillMode: Image.PreserveAspectCrop
        // Hidden until it is actually loaded, so a 404 from a stale art URL
        // leaves the placeholder rather than Qt's broken-image glyph.
        visible: status === Image.Ready
        asynchronous: true
        sourceSize: Qt.size(44, 44)   // 2x, downscaled so it stays crisp
      }
    }

    // Four crimson bars. They animate only while playing and FREEZE on pause --
    // `paused`, not `running`, because stopping the animation would snap every
    // bar back to its starting height and read as a reset rather than a hold.
    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      height: 12

      Repeater {
        model: 4

        Rectangle {
          required property int index
          anchors.verticalCenter: parent.verticalCenter
          width: 2
          height: 5
          color: Theme.accent

          SequentialAnimation on height {
            running: true
            paused: !MprisService.playing
            loops: Animation.Infinite
            // Staggered per bar, or four bars rising together is one thick bar.
            NumberAnimation {
              to: 4 + index * 2
              duration: 380 + index * 90
              easing.type: Easing.InOutSine
            }
            NumberAnimation {
              to: 12 - index * 2
              duration: 420 - index * 60
              easing.type: Easing.InOutSine
            }
          }
        }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      // 150px is the design's truncation point, and it is a hard cap rather
      // than a preferred width: a 40-minute mix title would otherwise push the
      // clock off centre.
      width: Math.min(implicitWidth, 150)
      elide: Text.ElideRight
      text: MprisService.title || MprisService.identity
      font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
      color: Theme.alpha(Theme.text, 0.8)
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.clicked()

    // Scroll changes the PLAYER's volume, not the sink's: the sink already has
    // the same gesture on the status pill's volume slot, and doing it twice
    // would make the two pills fight over one number.
    onWheel: wheel => {
      if (!MprisService.volumeSupported) return
      MprisService.setVolume(MprisService.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
    }
  }
}
