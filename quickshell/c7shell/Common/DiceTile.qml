import QtQuick
import qs.Theme
import "Pips.js" as Pips

// The workspace tile whose pip layout IS the workspace number: 1-6 die faces,
// 7-12 dominos, 13+ the numeral. Drawn in the bar and in the workspace OSD --
// the OSD used to carry its own 1-5 copy of the face table and went blank on
// workspace 6.
//
// Dots scale with the tile, so a 17px OSD tile and a 20px bar tile read the
// same. The caller owns the background: focus, urgency and the OSD's accent
// fill are its business, not the geometry's.
Rectangle {
  id: root

  required property int value
  property int tile: 20
  property color dotColor: Theme.text

  readonly property var face: Pips.layout(root.value)
  readonly property real dotSize: root.face.dotSize * (root.tile / 20)

  width: root.tile
  height: root.tile
  radius: Theme.radiusPip

  Repeater {
    model: root.face.dots

    Rectangle {
      required property var modelData
      x: modelData[0] * root.tile - root.dotSize / 2
      y: modelData[1] * root.tile - root.dotSize / 2
      width: root.dotSize
      height: root.dotSize
      radius: root.dotSize / 2
      color: root.dotColor
    }
  }

  // Domino mid divider (7-12)
  Rectangle {
    visible: root.face.divider
    x: 4
    width: root.tile - 8
    height: 1
    y: root.tile / 2 - 0.5
    color: Theme.alpha(Theme.text, 0.25)
  }

  // 13+ fallback: the number itself
  Text {
    visible: root.face.numeral
    anchors.centerIn: parent
    text: root.value
    color: root.dotColor
    font.family: Theme.fontMono
    font.pixelSize: Math.round(root.tile * 0.45)
    font.weight: 700
  }
}
