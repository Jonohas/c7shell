pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.Theme

// The fingerprint as nine ridges that light up one by one: the enroll sheet
// fills it scan by scan, the password prompt breathes it while the reader
// listens. The ridges are Assets/icons/fingerprint.svg's own paths, drawn as a
// Shape rather than through Icon, because an Image can only be tinted whole.
//
//   fill       0..1, how many ridges are lit, centre outwards
//   listening  the unlit ridges breathe -- the reader is waiting for a touch
//   success    every ridge in Theme.success
//   tap()      a short bounce, for a scan that landed
//   reject()   a shake and a red flash, for one that did not
Item {
  id: root

  property real size: 64
  property real fill: 0
  property bool listening: false
  property bool success: false
  property color litColor: Theme.accent

  implicitWidth: root.size
  implicitHeight: root.size

  // Centre outwards, so filling reads as the print growing from the core.
  readonly property var ridges: [
    "M12 10a2 2 0 0 0-2 2c0 1.02-.1 2.51-.26 4",
    "M14 13.12c0 2.38 0 6.38-1 8.88",
    "M9 6.8a6 6 0 0 1 9 5.2v2",
    "M5 19.5C5.5 18 6 15 6 12a6 6 0 0 1 .34-2",
    "M8.65 22c.21-.66.45-1.32.57-2",
    "M17.29 21.02c.12-.6.43-2.3.5-3.02",
    "M2 12a10 10 0 0 1 18-6",
    "M21.8 16c.2-2 .131-5.354 0-6",
    "M2 16h.01"
  ]
  readonly property int lit: root.success ? root.ridges.length
                                          : Math.round(root.fill * root.ridges.length)

  function tap() { bounce.restart() }
  function reject() { shake.restart(); flash.restart() }

  property real breath: 0.16
  property real flashing: 0

  SequentialAnimation on breath {
    running: root.listening && !root.success
    loops: Animation.Infinite
    NumberAnimation { to: 0.42; duration: 900; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0.16; duration: 900; easing.type: Easing.InOutSine }
    onStopped: root.breath = 0.16
  }

  SequentialAnimation {
    id: flash
    NumberAnimation { target: root; property: "flashing"; to: 1; duration: 80 }
    NumberAnimation { target: root; property: "flashing"; to: 0; duration: 420 }
  }

  Item {
    id: body
    anchors.fill: parent
    transform: Translate { id: nudge }

    SequentialAnimation {
      id: bounce
      NumberAnimation { target: body; property: "scale"; to: 1.08; duration: 110; easing.type: Easing.OutQuad }
      NumberAnimation { target: body; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
    }

    SequentialAnimation {
      id: shake
      NumberAnimation { target: nudge; property: "x"; to: -6; duration: 50 }
      NumberAnimation { target: nudge; property: "x"; to: 6; duration: 70 }
      NumberAnimation { target: nudge; property: "x"; to: -3; duration: 60 }
      NumberAnimation { target: nudge; property: "x"; to: 0; duration: 50 }
    }

    // One Shape per ridge: a Repeater can stamp Items, not ShapePaths.
    Repeater {
      model: root.ridges

      Shape {
        id: ridge
        required property string modelData
        required property int index

        readonly property bool on: ridge.index < root.lit
        readonly property color base: ridge.on
          ? (root.success ? Theme.success : root.litColor)
          : Theme.alpha(Theme.text, root.breath)

        // Authored in the SVG's 24-unit box and scaled, so the paths stay verbatim.
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: root.size / 24
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeWidth: 1.6
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin
          strokeColor: Qt.tint(ridge.base, Theme.alpha(Theme.accent, root.flashing * 0.9))
          Behavior on strokeColor { ColorAnimation { duration: 220 } }

          PathSvg { path: ridge.modelData }
        }
      }
    }
  }
}
