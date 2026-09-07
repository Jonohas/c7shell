import QtQuick

// The battery pictogram, drawn rather than read from an SVG -- the one icon on
// this bar that is not a lucide glyph, for the reason the shell's
// Common/BatteryGlyph.qml gives: lucide's battery is a 2px border and a
// detached nub on a 24 box, and beside these 1.1px strokes it reads as a
// foreign object. A recessive outline with the FILL carrying the state is what
// makes it sit in the same row as the wi-fi and caps-lock glyphs.
//
// Scaled from the greeter's mockup units like everything else here, so it
// tracks Theme.s with the icons beside it.
Item {
  id: root

  // -1 when there is no battery; the caller hides the pill rather than passing
  // it on, but the clamp below keeps a stray value inside the shell.
  property int level: 0
  property bool charging: false
  property color outline: Theme.ink(0.5)

  readonly property real fraction: Math.max(0, Math.min(100, root.level)) / 100
  // Crimson when it is nearly out, accentSoft on AC, the palette's warning
  // colour otherwise -- the same three states the pill's percentage reads in.
  readonly property color fill: root.charging ? Theme.accentSoft
    : root.level <= 15 ? Theme.accent
    : Theme.battery

  implicitWidth: Theme.px(14)
  implicitHeight: Theme.px(8)

  Rectangle {   // body
    width: root.width - Math.max(1, root.width * (2 / 14))
    height: root.height
    radius: Math.max(2, root.height * 0.35)
    color: "transparent"
    border.width: 1
    border.color: root.outline

    Rectangle {   // charge fill
      x: 2
      y: 2
      // A sliver at 0% still reads as a battery; zero width reads as a fault.
      width: Math.max(1, (parent.width - 4) * root.fraction)
      height: parent.height - 4
      radius: 1
      color: root.fill
    }
  }

  Rectangle {   // nub, flush against the body
    x: root.width - Math.max(1, root.width * (2 / 14))
    y: root.height * 0.28
    width: Math.max(1, root.width * (2 / 14))
    height: root.height * 0.44
    radius: 1
    color: root.outline
  }
}
