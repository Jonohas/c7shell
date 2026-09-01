import QtQuick
import Quickshell.Bluetooth
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings

// The full-size 1f: same BluetoothService, with the connect / pair / forget
// affordances split out per row instead of one click doing whatever fits.
SettingsPage {
  id: root

  title: "Bluetooth"
  subtitle: BluetoothService.adapter
    ? `${BluetoothService.adapter.name} · ${BluetoothService.enabled ? "on" : "off"}`
    : "no adapter"

  // Discovery follows the page. The bluetooth popover writes the same flag, so
  // opening and closing it over this page stops the scan until the page is
  // re-entered.
  Component.onCompleted: BluetoothService.wantScan = true
  Component.onDestruction: BluetoothService.wantScan = false

  // -- radio -----------------------------------------------------------------
  SettingsCard {
    width: parent.width

    Item {
      width: parent.width
      implicitHeight: 17

      Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "bluetooth"
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.alpha(Theme.text, 0.85)
      }
      TogglePill {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        checked: BluetoothService.enabled
        enabled: BluetoothService.adapter !== null
        onToggled: BluetoothService.setEnabled(!BluetoothService.enabled)
      }
    }
  }

  // -- connected -------------------------------------------------------------
  SectionLabel {
    text: "connected"
    visible: BluetoothService.connectedDevices.length > 0
  }

  SettingsCard {
    width: parent.width
    visible: BluetoothService.connectedDevices.length > 0
    padH: 4
    spacing: 2

    Repeater {
      model: Bluetooth.devices

      DeviceRow {
        required property var modelData
        width: parent.width
        device: modelData
        visible: modelData.connected
      }
    }
  }

  // -- everything in range ---------------------------------------------------
  Item {
    width: parent.width
    implicitHeight: 18

    SectionLabel {
      id: nearbyLabel
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      text: BluetoothService.enabled ? "nearby" : "bluetooth is off"
    }
    Spinner {
      anchors { left: nearbyLabel.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
      visible: BluetoothService.discovering
    }
    ActionChip {
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      text: BluetoothService.discovering ? "scanning…" : "⟳ scan"
      onTriggered: BluetoothService.scan()
    }
  }

  SettingsCard {
    width: parent.width
    visible: BluetoothService.enabled
    padH: 4
    spacing: 2

    // The ObjectModel goes in as-is and the delegate filters: a rebuilt JS
    // array of its objects as `model` segfaults when a device disappears
    // between a scan and the next regenerate.
    Repeater {
      model: Bluetooth.devices

      DeviceRow {
        required property var modelData
        width: parent.width
        device: modelData
        visible: !modelData.connected
      }
    }
  }

  component DeviceRow: ListRow {
    id: row

    required property var device

    readonly property int battery: BluetoothService.batteryPercent(row.device)
    readonly property bool paired: row.device.paired || row.device.bonded

    implicitHeight: 40
    leadingSize: 14
    active: row.device.connected
    title: BluetoothService.label(row.device)
    subtitle: BluetoothService.subtitle(row.device)
    // A bare MAC is a stranger's device more often than not.
    opacity: BluetoothService.named(row.device) ? 1 : 0.55

    onClicked: BluetoothService.activate(row.device)

    leading: Icon {
      name: "bluetooth"
      size: 14
      tint: row.device.connected ? Theme.accentSoft : Theme.alpha(Theme.text, 0.5)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: row.battery >= 0
      text: `▮ ${row.battery}%`
      font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
      color: Theme.alpha(Theme.text, 0.5)
    }
    ActionChip {
      anchors.verticalCenter: parent.verticalCenter
      visible: row.paired && row.hovered
      accented: false
      text: "forget"
      onTriggered: BluetoothService.forget(row.device)
    }
    ActionChip {
      anchors.verticalCenter: parent.verticalCenter
      visible: !row.paired
      text: "pair"
      onTriggered: BluetoothService.pairDevice(row.device)
    }
    ActionChip {
      anchors.verticalCenter: parent.verticalCenter
      visible: row.paired
      accented: row.device.connected
      text: row.device.connected ? "disconnect" : "connect"
      onTriggered: row.device.connected ? row.device.disconnect() : row.device.connect()
    }
  }
}
