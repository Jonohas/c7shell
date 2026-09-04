import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// The bar's battery widget, per the topbar handoff: glyph, optional percentage,
// optional signed draw, a hairline between the two numbers when both are on.
// Nothing here is a mock -- the settings page's preview is this same component.
//
// Both number fields reserve the width of the widest string they can ever hold,
// so the whole right-hand cluster stays put as the draw fluctuates. JetBrains
// Mono is monospaced, which makes that a simple max over the candidates rather
// than a tabular-figure font feature.
Row {
  id: root

  spacing: 8

  // The bar drives this from the hit target that wraps the widget; standalone
  // uses (the settings preview) leave it false and get no tooltip.
  property bool hovered: false

  // The crimson-tinted state, published so whatever owns the pill around this
  // -- the bar's QuickSlot -- can tint itself to match.
  readonly property bool warn: BatteryService.warn

  readonly property bool showPercent: ShellStore.batteryPercentage
  readonly property bool showWatts: BatteryService.showWatts

  BatteryGlyph {
    anchors.verticalCenter: parent.verticalCenter
  }

  Text {
    id: percentText

    anchors.verticalCenter: parent.verticalCenter
    visible: root.showPercent
    // Only the field the percentage lives in is reserved, not the whole widget:
    // turning the number off should actually shrink the pill.
    width: visible ? percentMetrics.width : 0
    horizontalAlignment: Text.AlignRight
    text: `${BatteryService.percent}%`
    // Weight 600 below the threshold: the pill is already crimson, and the
    // number is the thing being said.
    font { family: Theme.fontMono; pixelSize: 10; weight: root.warn ? 600 : 500 }
    color: root.warn ? Theme.text : Theme.alpha(Theme.text, 0.8)
  }

  TextMetrics {
    id: percentMetrics
    font: percentText.font
    text: "100%"
  }

  Rectangle {   // hairline, only when both numbers are present
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showPercent && root.showWatts
    width: 1
    height: 12
    color: root.warn ? Theme.alpha(Theme.accent, 0.3) : Theme.alpha(Theme.text, 0.12)
  }

  Text {
    id: wattText

    anchors.verticalCenter: parent.verticalCenter
    visible: root.showWatts
    width: visible ? wattMetrics.width : 0
    horizontalAlignment: Text.AlignRight
    text: BatteryService.wattText
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: BatteryService.idleOnPower ? Theme.alpha(Theme.text, 0.45)
      : BatteryService.charging ? Theme.success
      : Theme.accentSoft
  }

  TextMetrics {
    id: wattMetrics
    font: wattText.font
    // "on power" is longer than a two-digit draw and shorter than a three-digit
    // one, so the reservation has to be the max of both, not just the number.
    text: BatteryService.widestWattText.length >= "on power".length
      ? BatteryService.widestWattText : "on power"
  }

  // -- hover tooltip ---------------------------------------------------------
  // Everything the bar deliberately leaves out. Time remaining lives only here,
  // which is what its settings toggle is labelled after.
  component TipRow: Item {
    id: tipRow

    required property string key
    required property string value

    width: parent ? parent.width : 0
    implicitHeight: 12

    Text {
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      text: tipRow.key
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.45)
    }
    Text {
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      text: tipRow.value
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text
    }
  }

  Tooltip {
    id: tip

    visible: root.hovered
    anchorItem: root
    panelHeight: rows.implicitHeight + 22
    panelRadius: Theme.radiusMenu

    Column {
      id: rows

      anchors {
        left: parent.left; right: parent.right; top: parent.top
        leftMargin: 12; rightMargin: 12; topMargin: 11
      }
      spacing: 6

      TipRow {
        key: "charge"
        value: `${BatteryService.percent}% · ${BatteryService.energyWh.toFixed(1)} Wh`
      }
      TipRow {
        key: "draw"
        value: BatteryService.idleOnPower
          ? "on power" : `${BatteryService.watts.toFixed(1)} W`
      }
      TipRow {
        // The estimate is UPower's, and it is missing for the first minute
        // after a state change -- an absent row beats "0 m".
        visible: ShellStore.batteryTimeRemaining && BatteryService.secondsLeft > 0
        key: BatteryService.charging ? "until full" : "remaining"
        value: BatteryService.duration(BatteryService.secondsLeft)
      }
      TipRow {
        visible: BatteryService.health >= 0
        key: "health"
        value: `${BatteryService.health}%`
      }
      TipRow {
        // Plenty of packs do not export a cycle count at all.
        visible: BatteryService.cycles > 0
        key: "cycles"
        value: `${BatteryService.cycles}`
      }
    }
  }
}
