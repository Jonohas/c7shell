import QtQuick
import qs.Theme
import qs.Services

// The recording section inside the clock pill (mockup 5b): crimson dot, elapsed
// time and stop drawn on the pill's own background, shown right of the time
// behind a divider while recording. The clock, media and tray all stay put.
// The mockup's pause control is dropped: wf-recorder has no pause signal
// (SIGINT/SIGTERM/SIGHUP all end the recording), so showing ⏸ would lie.
Item {
  id: root
  implicitWidth: content.implicitWidth
  implicitHeight: Theme.pillHeight

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 10

    Rectangle {   // live dot, pulsing to read as "recording"
      anchors.verticalCenter: parent.verticalCenter
      width: 6; height: 6; radius: 3
      color: Theme.accentSoft

      SequentialAnimation on opacity {
        running: true
        loops: Animation.Infinite
        NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: RecordingService.elapsedText
      font { family: Theme.fontMono; pixelSize: 12; weight: 700 }
      color: Theme.accentSoft
    }
    // Stop is DRAWN, not a glyph: JetBrains Mono has no ■, so Text fell back
    // to the emoji font and ignored colour and opacity.
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 8; height: 8; radius: 1
      color: Theme.accentSoft
      MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: RecordingService.stop() }
    }
  }
}
