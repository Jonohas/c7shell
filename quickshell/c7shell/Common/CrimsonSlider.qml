import QtQuick
import QtQuick.Effects
import qs.Theme

// Spec §4 slider: 5px track r3, crimson fill with a `0 0 12px` glow, white 13px
// thumb. `softFill` is the input variant from 1g; dropping the thumb gives the
// 4px per-app mixer track from the same mock.
Item {
  id: root

  property real value: 0            // 0..1
  property bool softFill: false
  property bool thumb: true
  property int trackHeight: 5
  property color fillColor: root.softFill ? Theme.accentSoftFill : Theme.accent

  // Emitted while dragging, with the new 0..1 position.
  signal moved(real value)

  implicitHeight: root.thumb ? 13 : root.trackHeight
  // Same as TogglePill and Segmented: a slider whose row is disabled shows
  // itself as dead. Without this the MouseArea goes deaf while the track keeps
  // looking live, which is the one combination that reads as a bug.
  opacity: root.enabled ? 1 : 0.4

  Rectangle {
    id: track

    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
    height: root.trackHeight
    radius: height / 2
    color: Theme.surface10

    Rectangle {
      id: fill
      width: track.width * Math.max(0, Math.min(1, root.value))
      height: parent.height
      radius: parent.radius
      color: root.fillColor
    }

    // RectangularShadow rather than MultiEffect: MultiEffect paints its source,
    // which would double the fill on top of itself.
    RectangularShadow {
      anchors.fill: fill
      radius: fill.radius
      color: Theme.sliderGlowColor
      blur: 12
      visible: root.thumb && root.value > 0
      z: -1
    }
  }

  Rectangle {
    visible: root.thumb
    x: Math.max(0, Math.min(track.width - width, track.width * Math.max(0, Math.min(1, root.value)) - width / 2))
    anchors.verticalCenter: parent.verticalCenter
    width: 13
    height: 13
    radius: 6.5
    color: Theme.textOnAccent
  }

  MouseArea {
    anchors.fill: parent
    // Vertical slop so a 4px track is still grabbable.
    anchors.topMargin: -4
    anchors.bottomMargin: -4
    // A slider inside a Flickable -- every settings page is one, once the window
    // is short enough to scroll -- otherwise loses the drag the moment the
    // pointer wanders a few px up or down: the Flickable decides the gesture was
    // a flick and steals the grab, and the value freezes mid-drag. Holding the
    // button is the user saying which one they meant.
    preventStealing: true

    function seek(x) {
      root.moved(Math.max(0, Math.min(1, x / track.width)))
    }

    onPressed: mouse => seek(mouse.x)
    onPositionChanged: mouse => seek(mouse.x)
  }
}
