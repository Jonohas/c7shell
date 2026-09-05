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

    ListRow {
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

    // The link's own gateway, read from the wi-fi device: the address the
    // connected row carries is this machine's, and neither of them is the other.
    ListRow {
      width: parent.width
      visible: NetworkService.gateway !== ""
      hoverable: false
      leadingSize: 15
      title: "gateway"
      subtitle: `${NetworkService.interfaceName} · default route`

      leading: Icon {
        size: 15
        name: "ethernet"
        tint: Theme.text3
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: NetworkService.gateway
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        color: Theme.accentSoft
      }
    }

    // Metered is a property of the saved profile, so there has to be a link to
    // save it against. "auto" is NetworkManager's own guess -- worth keeping as
    // a choice, because it is the only one that follows the network rather than
    // being remembered against it.
    ListRow {
      width: parent.width
      visible: NetworkService.connected !== null
      hoverable: false
      leadingSize: 15
      title: "metered connection"
      subtitle: NetworkService.meteredChoice === "unknown"
        ? `guessed · treated as ${NetworkService.metered ? "metered" : "unmetered"}`
        : NetworkService.metered
          ? "saved on this network · background transfers held back"
          : "saved on this network · no limits applied"

      leading: Icon {
        size: 15
        name: "gauge"
        tint: NetworkService.metered ? Theme.accentSoft : Theme.text3
      }

      Segmented {
        anchors.verticalCenter: parent.verticalCenter
        options: [
          { value: "unknown", label: "auto" },
          { value: "yes", label: "metered" },
          { value: "no", label: "unmetered" }
        ]
        value: NetworkService.meteredChoice
        onPicked: v => NetworkService.setMetered(v)
      }
    }

    // Sits in the radio card because that is what it switches -- all of them,
    // through rfkill, which is also what the laptop's own airplane key throws.
    // So this row and the Fn key mean the same thing, and unlike the wi-fi
    // toggle above it can undo a block the key made.
    ListRow {
      width: parent.width
      visible: AirplaneService.hasWifi || AirplaneService.hasBt
      hoverable: false
      leadingSize: 15
      title: "airplane mode"
      subtitle: AirplaneService.enabled
        ? `${root.radioNames} off · wired networking untouched`
        : `switches ${root.radioNames} off`

      leading: Icon {
        size: 15
        name: "plane"
        tint: AirplaneService.enabled ? Theme.accentSoft : Theme.text3
      }

      TogglePill {
        anchors.verticalCenter: parent.verticalCenter
        checked: AirplaneService.enabled
        onToggled: AirplaneService.setEnabled(!AirplaneService.enabled)
      }
    }
  }

  // Named rather than assumed: a desktop with a wi-fi card and no bluetooth
  // adapter would otherwise be promised bluetooth it does not have.
  readonly property string radioNames: [
    AirplaneService.hasWifi ? "wi-fi" : "",
    AirplaneService.hasBt ? "bluetooth" : "",
  ].filter(s => s !== "").join(" and ")

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

    // SSIDs go in, not the networks: the ObjectModel is safe to pass but
    // arrives in NetworkManager's own order, which is not signal order at all,
    // and a JS array of the objects as `model` segfaults when one of them is
    // destroyed between a rescan and the next regenerate. The row looks its
    // network back up and unloads with it, so nothing here binds to an object
    // that is already gone.
    Repeater {
      model: NetworkService.otherNames

      Loader {
        id: slot
        required property var modelData
        readonly property var network: NetworkService.byName(slot.modelData)

        width: parent.width
        active: slot.network !== null
        visible: slot.active
        sourceComponent: NetworkRow {
          width: slot.width
          network: slot.network
        }
      }
    }
  }

  // A row grows its password field underneath rather than opening a dialog.
  // The field and the ask-for-a-key rule live in Common/PskField, shared with
  // the popover -- this page used to have neither and joined blind.
  component NetworkRow: Column {
    id: row

    required property var network

    ListRow {
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
