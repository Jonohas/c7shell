import QtQuick
import QtQuick.Effects
import qs.Theme
import qs.Services

// Replaces ClockPill while recording (mockup 5b): solid crimson pill with
// elapsed time and stop. The ONLY topbar change during recording.
// The mockup's pause control is dropped: wf-recorder has no pause signal
// (SIGINT/SIGTERM/SIGHUP all end the recording), so showing ⏸ would lie.
Rectangle {
  id: root
  implicitWidth: content.implicitWidth + 28   // content tuning, not a token
  implicitHeight: Theme.pillHeight
  radius: Theme.pillRadius
  color: Theme.alpha(Theme.accent, 0.85)

  RectangularShadow {   // crimson glow, spec 5b
    anchors.fill: parent
    radius: root.radius
    color: Theme.accentGlow
    offset: Qt.vector2d(0, 0)
    blur: 12
    z: -1
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 10

    Rectangle {   // live dot
      anchors.verticalCenter: parent.verticalCenter
      width: 6; height: 6; radius: 3
      color: Theme.text
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: RecordingService.elapsedText
      font { family: Theme.fontMono; pixelSize: 12; weight: 700 }
      color: Theme.text
    }
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 1; height: 12
      color: Theme.alpha(Theme.text, 0.35)
    }
    // Stop is DRAWN, not a glyph: JetBrains Mono has no ■, so Text fell back
    // to the emoji font and ignored colour and opacity.
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 8; height: 8; radius: 1
      color: Theme.text
      MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: RecordingService.stop() }
    }
  }
}
