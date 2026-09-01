import QtQuick
import qs.Theme
import qs.Services

Rectangle {
  id: root
  signal clicked()

  implicitWidth: content.implicitWidth + 28   // content tuning, not a token
  implicitHeight: Theme.pillHeight
  radius: Theme.pillRadius
  color: mouse.containsMouse ? Theme.surface07 : Theme.surface05

  // Track-change flash: the pill's border pulses crimson for ~1s when the
  // playing track changes, the island-mode stand-in for the bottom-centre OSD.
  // 0 at rest, so the border is invisible until a change drives `pulse` to 1.
  property real pulse: 0
  border.width: 1
  border.color: Theme.alpha(Theme.accent, 0.35 * pulse)

  NumberAnimation {
    id: flash
    target: root; property: "pulse"
    from: 1; to: 0; duration: 900; easing.type: Easing.OutCubic
  }

  Connections {
    target: MprisService
    // trackId is uniqueId␟title, so it changes on the actual next track, not on
    // a metadata refresh of the same one. Only in compact style, and only while
    // playing, so a paused skip does not strobe the bar.
    function onTrackIdChanged() {
      if (ShellStore.mediaPillStyle === "compact" && MprisService.playing
          && MprisService.trackId !== "")
        flash.restart()
    }
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 10

    // Dynamic-island media signal: in "compact" media style the standalone
    // MediaPill is gone, and this is the only "something is playing" cue. Three
    // eq bars in the time-text tone, then a hairline before the date. Both hide
    // when nothing is registered, and Row drops their spacing with them, so an
    // idle bar is the clock alone with no gap where the bars would sit.
    Row {
      id: eq
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      height: 12
      visible: ShellStore.mediaPillStyle === "compact" && MprisService.hasPlayer

      Repeater {
        model: 3

        Rectangle {
          required property int index
          // Anchored to the bottom, so the bar grows UP from a fixed baseline
          // rather than out from its centre -- centre-growth reads as jitter.
          anchors.bottom: parent.bottom
          width: 3
          height: 4
          radius: 1.5
          // Paused freezes the bars low and dims them, so the session still
          // reads as reachable rather than stopped.
          color: Theme.accentSoft
          opacity: MprisService.playing ? 1 : 0.45

          // One ~1s ease-in-out cycle per bar, all identical, phase-offset by a
          // one-shot lead pause (0/0.22/0.44s) so the three read as an
          // equalizer instead of one thick bar -- the design's dv-eq keyframes.
          // paused (not stopped) on pause, so the bars FREEZE in place rather
          // than snapping back to a reset height.
          SequentialAnimation on height {
            running: true
            paused: !MprisService.playing
            PauseAnimation { duration: index * 220 }
            SequentialAnimation {
              loops: Animation.Infinite
              NumberAnimation { to: 12; duration: 520; easing.type: Easing.InOutSine }
              NumberAnimation { to: 4; duration: 520; easing.type: Easing.InOutSine }
            }
          }
        }
      }
    }
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      visible: eq.visible
      width: 1; height: 12
      color: Theme.hairlineStrong
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: Time.dateLine
      font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
      color: Theme.alpha(Theme.text, 0.75)
    }
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 1; height: 12
      color: Theme.hairlineStrong
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: Time.hm
      font { family: Theme.fontMono; pixelSize: 12; weight: 700 }
      color: Theme.accentSoft
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.clicked()   // SP2 opens the calendar popover here
  }
}
