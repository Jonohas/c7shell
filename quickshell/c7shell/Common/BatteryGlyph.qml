import QtQuick
import qs.Theme
import qs.Services

// The battery pictogram: outlined body, a fill that IS the charge, a nub, and a
// bolt while charging. Everything is laid out in the design's 16x16 box and
// scaled from there, so a size change moves the whole drawing together instead
// of drifting apart a pixel at a time.
//
// Colour carries state on its own: amber discharging, green charging, grey idle
// on AC, crimson below the warn threshold.
Item {
  id: root

  property real size: 15

  // The pieces read state directly so the bar and the settings preview cannot
  // disagree about what the battery is doing.
  readonly property real u: root.size / 16
  readonly property bool warn: BatteryService.warn

  readonly property color outline: root.warn
    ? Theme.accentSoft : Theme.alpha(Theme.text, 0.6)

  readonly property color fill: root.warn ? Theme.accent
    : BatteryService.charging ? Theme.success
    : BatteryService.idleOnPower ? Theme.alpha(Theme.text, 0.55)
    : "#e0b341"

  width: root.size
  height: root.size

  Rectangle {   // body
    x: 1.5 * root.u
    y: 5 * root.u
    width: 11 * root.u
    height: 6.5 * root.u
    radius: 1.6 * root.u
    color: "transparent"
    border.width: Math.max(1, 1.2 * root.u)
    border.color: root.outline

    Rectangle {   // the charge itself, 8 units wide at 100%
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

  Rectangle {   // nub
    x: 13.3 * root.u
    y: 7 * root.u
    width: 1.4 * root.u
    height: 2.5 * root.u
    radius: width / 2
    color: root.outline
  }

  Icon {   // charging bolt, drawn in the same 16x16 box as everything above
    visible: BatteryService.charging
    name: "battery-bolt"
    size: root.size
    tint: Theme.success
  }
}
