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
//
// `mode` is the topbar setting: the pips are the shell's own idiom, but plain
// numerals and hyprland's workspace names are both legitimate answers, and the
// same tile draws all three so focus, urgency and glow behave identically.
Rectangle {
  id: root

  required property int value
  property int tile: 20
  property color dotColor: Theme.text

  // dice | numerals | names
  property string mode: "dice"
  // Only consulted in `names` mode, and only when hyprland actually has a name
  // for the workspace -- an unnamed one falls back to its number rather than to
  // an empty tile.
  property string label: ""

  readonly property var face: Pips.layout(root.value)
  readonly property real dotSize: root.face.dotSize * (root.tile / 20)

  readonly property bool pips: root.mode === "dice" && !root.face.numeral
  readonly property string captionText: root.mode === "names" && root.label !== ""
    ? root.label : `${root.value}`

  // A name needs room; a numeral does not. Padding is on the text, so the tile
  // stays exactly square whenever it holds one glyph or a pip face.
  width: root.pips ? root.tile : Math.max(root.tile, caption.implicitWidth + 12)
  height: root.tile
  radius: Theme.radiusPip

  Repeater {
    model: root.pips ? root.face.dots : []

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
    visible: root.pips && root.face.divider
    x: 4
    width: root.tile - 8
    height: 1
    y: root.tile / 2 - 0.5
    color: Theme.alpha(Theme.text, 0.25)
  }

  // Whatever the pips cannot say: the 13+ fallback, and both of the non-dice
  // modes.
  Text {
    id: caption

    visible: !root.pips
    anchors.centerIn: parent
    text: root.captionText
    color: root.dotColor
    font.family: Theme.fontMono
    font.pixelSize: Math.round(root.tile * 0.45)
    font.weight: 700
  }
}
