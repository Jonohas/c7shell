import QtQuick
import Quickshell.Services.UPower
import qs.Theme
import qs.Common

// 1h: same icon+% slot in the bar; the fill color carries the state and a
// glyph overlays the fill. discharging = crimson fill · charging = green fill
// + bolt, green % · on-power-not-charging = grey fill + plug · critical =
// crimson outline + crimson %.
Row {
  id: root
  spacing: 5

  readonly property var battery: UPower.displayDevice
  readonly property real pct: battery?.percentage ?? 0
  readonly property int st: battery?.state ?? 0

  readonly property bool charging: st === UPowerDeviceState.Charging
  readonly property bool onPower: st === UPowerDeviceState.FullyCharged
    || st === UPowerDeviceState.PendingCharge
  readonly property bool critical: !charging && !onPower && pct <= 0.10

  Item {
    anchors.verticalCenter: parent.verticalCenter
    width: 20; height: 11

    Rectangle {   // body
      width: 18; height: 11; radius: 2.5
      color: "transparent"
      border.width: 1
      border.color: root.critical ? Theme.accent : Theme.hairlineStrong

      Rectangle {   // charge fill
        x: 2; y: 2
        width: Math.max(1, 14 * root.pct)
        height: 7; radius: 1.5
        color: root.charging ? Theme.success
          : root.onPower ? Theme.text3
          : Theme.accent
      }
      Icon {   // glyph overlays the fill
        anchors.centerIn: parent
        size: 7
        name: root.charging ? "zap" : "plug"
        visible: root.charging || root.onPower
        tint: Theme.text
      }
    }
    Rectangle {   // nub
      x: 18; y: 3
      width: 2; height: 5; radius: 1
      color: root.critical ? Theme.accent : Theme.hairlineStrong
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: `${Math.round(root.pct * 100)}%`
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: root.charging ? Theme.success
      : root.critical ? Theme.accentSoft
      : Theme.text2
  }
}
