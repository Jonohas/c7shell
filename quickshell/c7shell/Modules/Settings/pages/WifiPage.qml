import QtQuick
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings

// The full-size 1e: same NetworkService, but the whole scan list instead of a
// capped 240px flick, plus the saved/forget affordances a popover has no room
// for.
SettingsPage {
  id: root

  title: "Wi-Fi"
  subtitle: NetworkService.interfaceName !== ""
    ? `${NetworkService.interfaceName} · ${NetworkService.enabled ? "on" : "off"}`
    : "no wireless device"

  // Scanning follows the page, the way it follows the popover. If the wi-fi
  // popover is opened and closed over the top of this page it will clear the
  // flag; reopening the page starts it again.
  Component.onCompleted: NetworkService.wantScan = true
  Component.onDestruction: NetworkService.wantScan = false

  // -- radio + current link --------------------------------------------------
  SettingsCard {
    width: parent.width
    spacing: 12

    Item {
      width: parent.width
      implicitHeight: 17

      Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "wi-fi"
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.alpha(Theme.text, 0.85)
      }
      Text {
        id: blocked
        anchors { right: radio.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        visible: !NetworkService.hardwareEnabled
        text: "blocked in hardware"
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: Theme.accentSoft
      }
      TogglePill {
        id: radio
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        checked: NetworkService.enabled
        enabled: NetworkService.hardwareEnabled
        onToggled: NetworkService.setEnabled(!NetworkService.enabled)
      }
    }

    SettingsRow {
      width: parent.width
      visible: NetworkService.connected !== null
      active: true
      hoverable: false
      leadingSize: 15
      title: NetworkService.connected?.name ?? ""
      subtitle: `connected · ${NetworkService.securityLabel(NetworkService.connected)}`
        + (NetworkService.primary === "wifi" && NetworkService.ip !== "" ? ` · ${NetworkService.ip}` : "")

      leading: SignalArcs {
        size: 15
        tint: Theme.accentSoft
        strength: NetworkService.connected?.signalStrength ?? 0
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: `${NetworkService.dbm(NetworkService.connected?.signalStrength ?? 0)}dBm`
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        color: Theme.accentSoft
      }
      ActionChip {
        anchors.verticalCenter: parent.verticalCenter
        text: "disconnect"
        onTriggered: NetworkService.connected?.disconnect()
      }
    }
  }

  // -- everything else -------------------------------------------------------
  Item {
    width: parent.width
    implicitHeight: 18

    SectionLabel {
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      text: NetworkService.enabled ? "other networks" : "wi-fi is off"
    }
    ActionChip {
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      text: NetworkService.scanning ? "scanning…" : "⟳ rescan"
      onTriggered: NetworkService.rescan()
    }
  }

  SettingsCard {
    width: parent.width
    visible: NetworkService.enabled
    padH: 4
    spacing: 2

    // The ObjectModel goes in as-is and the delegate filters: a rebuilt JS
    // array of its objects as `model` segfaults when one of them is destroyed
    // between a rescan and the next regenerate.
    Repeater {
      model: NetworkService.device ? NetworkService.device.networks : null

      NetworkRow {
        required property var modelData
        width: parent.width
        network: modelData
        visible: modelData.name !== "" && !modelData.connected
      }
    }
  }

  // A row grows its password field underneath rather than opening a dialog.
  // The field and the ask-for-a-key rule live in Common/PskField, shared with
  // the popover -- this page used to have neither and joined blind.
  component NetworkRow: Column {
    id: row

    required property var network

    SettingsRow {
      id: line

      width: row.width
      implicitHeight: 38
      leadingSize: 14
      title: row.network.name
      subtitle: row.network.stateChanging
        ? "connecting…"
        : `${NetworkService.securityLabel(row.network)}${row.network.known ? " · saved" : ""}`

      leading: SignalArcs { size: 14; strength: row.network.signalStrength }

      onClicked: {
        // A network nobody has saved a key for cannot be joined by asking
        // NetworkManager to try -- that drops the association you are on. Ask
        // for the key first instead; connect() refuses it either way.
        if (psk.asking) psk.focusInput()
        else if (NetworkService.needsKey(row.network)) psk.ask()
        else NetworkService.connect(row.network)
      }

      ActionChip {
        anchors.verticalCenter: parent.verticalCenter
        visible: row.network.known && line.hovered
        text: "forget"
        onTriggered: NetworkService.forget(row.network)
      }
      Icon {
        anchors.verticalCenter: parent.verticalCenter
        visible: NetworkService.secured(row.network)
        name: "lock"
        size: 10
        tint: Theme.alpha(Theme.text, 0.4)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: `${NetworkService.dbm(row.network.signalStrength)}`
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: Theme.alpha(Theme.text, 0.35)
      }
    }

    PskField {
      id: psk
      width: row.width
      network: row.network
      padH: 12
    }
  }
}
