import QtQuick
import qs.Theme
import qs.Services

// The battery pictogram. Geometry is the bar's own, not the handoff's 16-unit
// box: the neighbouring icons are lucide at stroke-width 2 on a 24 viewBox --
// about 1.1px at the size they render -- so a 2px border, a detached nub and a
// filled bolt overhanging the corner all read as a foreign object next to them.
// A recessive 1px outline with the FILL carrying the state is what makes this
// sit in the same row as the wi-fi and volume glyphs.
//
// What the handoff does own here is the state model, which is the part that
// actually changed: the fill, the warn threshold, and the widget's colours.
Item {
  id: root

  readonly property bool warn: BatteryService.warn

  // Deliberately dim. The outline is the container, not the message -- pushing
  // it up to the other icons' full-text tint makes the battery shout over them,
  // and the fill inside it is what the eye is meant to land on.
  readonly property color outline: root.warn ? Theme.accent : Theme.hairlineStrong

  // Crimson out, green in, grey parked on AC -- the bar's existing language.
  // Below the threshold the escalation is the outline and the slot around it,
  // not a fourth fill colour.
  readonly property color fill: root.charging ? Theme.success
    : root.idleOnPower ? Theme.text3
    : Theme.accent

  readonly property bool charging: BatteryService.charging
  readonly property bool idleOnPower: BatteryService.idleOnPower

  width: 20
  height: 11

  Rectangle {   // body
    width: 18
    height: 11
    radius: 2.5
    color: "transparent"
    border.width: 1
    border.color: root.outline

    Rectangle {   // charge fill
      x: 2
      y: 2
      // A sliver at 0% still reads as a battery; zero width reads as a fault.
      width: Math.max(1, 14 * BatteryService.fraction)
      height: 7
      radius: 1.5
      color: root.fill

      Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 150 } }
    }

    Icon {   // the same lucide glyphs the rest of the row is drawn from
      anchors.centerIn: parent
      size: 7
      name: root.charging ? "zap" : "plug"
      visible: root.charging || root.idleOnPower
      tint: Theme.text
    }
  }

  Rectangle {   // nub, flush against the body
    x: 18
    y: 3
    width: 2
    height: 5
    radius: 1
    color: root.outline
  }
}
