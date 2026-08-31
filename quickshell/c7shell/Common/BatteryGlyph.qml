import QtQuick
import qs.Theme
import qs.Services

// The battery pictogram: outlined body, a fill that IS the charge, a nub, and a
// bolt while charging. Colour carries state on its own -- amber discharging,
// green charging, grey idle on AC, crimson below the warn threshold.
//
// The handoff draws this in a 16-unit box, but the battery only occupies 11 of
// those units across and 6.5 down: sizing the BOX to the design's 15px renders a
// pictogram barely half the size of the one the bar had. So the caller sizes the
// drawing instead -- `bodyHeight` is the outlined body, the thing you actually
// see -- and the item crops to what is drawn rather than to the box's slack.
// Everything else is in design units off that, so the proportions stay exact.
Item {
  id: root

  // 11px reproduces the bar's previous glyph; the design's own proportions then
  // make the body 18.6 wide against the 18 it used to be.
  property real bodyHeight: 11

  readonly property real u: root.bodyHeight / 6.5
  readonly property bool warn: BatteryService.warn

  readonly property color outline: root.warn
    ? Theme.accentSoft : Theme.alpha(Theme.text, 0.6)

  readonly property color fill: root.warn ? Theme.accent
    : BatteryService.charging ? Theme.success
    : BatteryService.idleOnPower ? Theme.alpha(Theme.text, 0.55)
    : "#e0b341"

  // The drawing runs from design x 1.5 to 14.7 and y 5 to 11.5; children below
  // are placed with that origin already subtracted.
  width: 13.2 * root.u
  height: 6.5 * root.u

  Rectangle {   // body
    width: 11 * root.u
    height: 6.5 * root.u
    radius: 1.6 * root.u
    color: "transparent"
    // Proportional to the design's 1.2 stroke, but snapped: a crisp 2px edge
    // reads better than an antialiased 1.98 one.
    border.width: Math.max(1, Math.round(1.2 * root.u))
    border.color: root.outline

    Rectangle {   // the charge itself, 8 design units wide at 100%
      x: 1.5 * root.u
      y: 1.5 * root.u
      // A hairline of fill at 0% still says "this is a battery"; zero width
      // would read as a rendering fault.
      width: Math.max(1, 8 * root.u * BatteryService.fraction)
      height: 3.5 * root.u
      radius: 0.6 * root.u
      color: root.fill

      Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }
  }

  Rectangle {   // nub, detached from the body exactly as the handoff draws it
    x: 11.8 * root.u
    y: 2 * root.u
    width: 1.4 * root.u
    height: 2.5 * root.u
    radius: width / 2
    color: root.outline
  }

  Icon {   // charging bolt: still placed in the full 16-unit box, shifted to
           // this item's cropped origin, so it overlaps the body's top-left and
           // pokes above it the way the design has it.
    x: -1.5 * root.u
    y: -5 * root.u
    visible: BatteryService.charging
    name: "battery-bolt"
    size: 16 * root.u
    tint: Theme.success
  }
}
