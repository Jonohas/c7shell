pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.Theme

// The fingerprint as nine ridges that light up one by one: the enroll sheet
// fills it scan by scan, the password prompt shows it whole while the reader
// listens. The ridges are Assets/icons/fingerprint.svg's own paths, drawn as a
// Shape rather than through Icon, because an Image can only be tinted whole.
//
//   fill       0..1, how many ridges are lit, centre outwards
//   listening  the unlit ridges breathe -- the reader is waiting for a touch
//   scanning   a beam of light sweeps up and down the ridges, and only the
//              ridges: it is a copy of the print, masked to a moving band
//   success    every ridge in Theme.success
//   tap()      a bounce and a ring rippling out, for a scan that landed
//   reject()   a shake, a red flash and a red ripple, for one that did not
Item {
  id: root

  property real size: 64
  property real fill: 0
  property bool listening: false
  property bool scanning: false
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

  function tap() { bounce.restart(); ripple.fire(root.success ? Theme.success : root.litColor) }
  function reject() { shake.restart(); flash.restart(); ripple.fire(Theme.accent) }

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

  // The print, once. `glow` paints every ridge in one bright colour for the
  // beam's copy; the base copy colours each ridge by its own state.
  component Ridges: Item {
    id: set
    // Inline components cannot see this file's ids, so the glyph is handed in.
    required property var g
    property bool glow: false
    anchors.fill: parent

    // One Shape per ridge: a Repeater can stamp Items, not ShapePaths.
    Repeater {
      model: set.g.ridges

      Shape {
        id: ridge
        required property string modelData
        required property int index

        readonly property bool on: ridge.index < set.g.lit
        readonly property color base: set.glow ? Qt.lighter(set.g.success ? Theme.success : set.g.litColor, 1.9)
          : ridge.on ? (set.g.success ? Theme.success : set.g.litColor)
          : Theme.alpha(Theme.text, set.g.breath)

        // Authored in the SVG's 24-unit box and scaled, so the paths stay verbatim.
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: set.g.size / 24
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeWidth: set.glow ? 2.0 : 1.6
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin
          strokeColor: set.glow ? ridge.base
            : Qt.tint(ridge.base, Theme.alpha(Theme.accent, set.g.flashing * 0.9))
          Behavior on strokeColor { ColorAnimation { duration: 220 } }

          PathSvg { path: ridge.modelData }
        }
      }
    }
  }

  // -- the ripple ----------------------------------------------------------
  // Behind the print, so the ring seems to come off the finger rather than
  // cross the ridges.
  Rectangle {
    id: ripple
    property color tint: root.litColor
    function fire(c) { ripple.tint = c; rippleAnim.restart() }

    anchors.centerIn: parent
    width: root.size * 0.5
    height: width
    radius: width / 2
    color: "transparent"
    border.width: 2
    border.color: ripple.tint
    opacity: 0

    ParallelAnimation {
      id: rippleAnim
      NumberAnimation { target: ripple; property: "width"; from: root.size * 0.5; to: root.size * 1.6; duration: 650; easing.type: Easing.OutCubic }
      NumberAnimation { target: ripple; property: "opacity"; from: 0.7; to: 0; duration: 650; easing.type: Easing.OutQuad }
      NumberAnimation { target: ripple; property: "border.width"; from: 3; to: 0.5; duration: 650 }
    }
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

    Ridges { g: root }

    // -- the beam ------------------------------------------------------------
    // A bright copy of the print, shown only through a soft horizontal band
    // that sweeps top to bottom and back. Masked rather than drawn over, so
    // the light lands on the ridges and never on the gaps between them.
    Ridges {
      id: bright
      g: root
      glow: true
      visible: false
      layer.enabled: root.scanning
    }

    Item {
      id: band
      anchors.fill: parent
      visible: false
      layer.enabled: root.scanning

      property real pos: -0.25

      Rectangle {
        width: parent.width
        height: parent.height * 0.34
        y: band.pos * parent.height - height / 2
        gradient: Gradient {
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: "white" }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }

      SequentialAnimation on pos {
        running: root.scanning
        loops: Animation.Infinite
        NumberAnimation { from: -0.25; to: 1.25; duration: 1300; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.25; to: -0.25; duration: 1300; easing.type: Easing.InOutSine }
      }
    }

    MultiEffect {
      anchors.fill: parent
      visible: root.scanning
      source: bright
      maskEnabled: true
      maskSource: band
      // A soft edge rather than a hard cut: the band's gradient alpha fades
      // the light in and out across the threshold.
      maskThresholdMin: 0.4
      maskSpreadAtMin: 0.8
      blurEnabled: true
      blurMax: 8
      blur: 0.15
    }
  }
}
