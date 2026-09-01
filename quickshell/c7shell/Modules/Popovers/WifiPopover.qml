import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// 1e: radio toggle, the link you are on, and everything else in range. All the
// NetworkManager handling is in NetworkService — this file only draws.
GlassPopover {
  id: root

  name: "wifi"
  panelWidth: 320
  gap: 10

  // Scanning follows the panel: on while it is open, off the moment it closes.
  onOpenChanged: NetworkService.wantScan = root.open

  Item {
    width: parent.width
    implicitHeight: 17

    Text {
      anchors { left: parent.left; right: iface.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
      text: "wi-fi"
      font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
      color: Theme.text
    }
    Text {
      id: iface
      anchors { right: toggle.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
      text: NetworkService.interfaceName
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.35)
    }
    TogglePill {
      id: toggle
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      checked: NetworkService.enabled
      // A hardware kill switch cannot be undone from software.
      enabled: NetworkService.hardwareEnabled
      onToggled: NetworkService.setEnabled(!NetworkService.enabled)
    }
  }

  // 1i: when the wire is the primary link the popover leads with it (2a card style).
  ListRow {
    width: parent.width
    visible: NetworkService.primary === "ethernet"
    implicitHeight: 46
    radius: Theme.radiusRow
    filled: true
    hoverable: false
    inset: 14
    leadingSize: 7
    titleColor: Theme.text
    subtitleColor: Theme.text2
    title: NetworkService.ethDevice?.name ?? ""
    subtitle: NetworkService.ip !== "" ? `connected · ${NetworkService.ip}` : "connected"

    leading: Rectangle {   // green status dot
      width: 7; height: 7; radius: 3.5
      color: Theme.success
    }
  }

  // -- the link you are on --------------------------------------------------
  ListRow {
    width: parent.width
    visible: NetworkService.connected !== null
    implicitHeight: 46
    radius: Theme.radiusRow
    active: true
    hoverable: false
    leadingSize: 15
    subtitleColor: Theme.alpha(Theme.text, 0.5)
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
  }

  SectionLabel {
    text: NetworkService.enabled ? "other networks" : "wi-fi is off"
  }

  // Capped so a street full of access points scrolls instead of growing a panel
  // taller than the screen.
  Flickable {
    id: list

    width: parent.width
    height: Math.min(contentHeight, 240)
    contentHeight: rows.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    visible: NetworkService.enabled

    Column {
      id: rows
      // The Flickable, not `parent`: children are parented to contentItem,
      // whose width tracks contentWidth rather than the viewport.
      width: list.width

      // SSIDs go in, not the networks: the ObjectModel is safe to pass but
      // arrives in NetworkManager's own order, which is not signal order at
      // all, and a JS array of the objects as `model` segfaults when one of
      // them is destroyed between a rescan and the next regenerate. The row
      // looks its network back up and unloads with it, so nothing here binds
      // to an object that is already gone.
      Repeater {
        model: NetworkService.otherNames

        Loader {
          id: slot
          required property var modelData
          readonly property var network: NetworkService.byName(slot.modelData)

          width: rows.width
          active: slot.network !== null
          visible: slot.active
          sourceComponent: NetworkRow {
            width: rows.width
            network: slot.network
          }
        }
      }
    }
  }

  // Radio on and nothing in range reads as a broken panel otherwise: the list
  // simply collapses and the section label sits over nothing. `others` is a
  // count here, never a model -- the rule above is about what a Repeater is
  // handed, not about naming the objects at all.
  Text {
    width: parent.width
    visible: NetworkService.enabled && NetworkService.others.length === 0
    text: NetworkService.scanning ? "looking for networks" : "nothing in range"
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: Theme.text3
    topPadding: 2
    bottomPadding: 4
  }

  // The master switch for every radio, not just this one. It sits under the
  // list rather than over the header because the header is this panel's title:
  // above it, "airplane mode" reads as the name of the popover. It is also the
  // only control here that can come back out of a block the Fn key made -- the
  // wi-fi toggle above cannot, which is why both are on screen at once.
  Item {
    width: parent.width
    visible: AirplaneService.hasWifi || AirplaneService.hasBt
    implicitHeight: 17

    Icon {
      id: planeIcon
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      name: "plane"
      size: 12
      tint: AirplaneService.enabled ? Theme.accentSoft : Theme.alpha(Theme.text, 0.45)
    }
    Text {
      anchors { left: planeIcon.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
      text: "airplane mode"
      font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
      color: Theme.text
    }
    TogglePill {
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      checked: AirplaneService.enabled
      onToggled: AirplaneService.setEnabled(!AirplaneService.enabled)
    }
  }

  PopoverFooter {
    width: parent.width
    leftIcon: "refresh"
    leftText: NetworkService.scanning ? "scanning" : "rescan"
    rightText: "network settings →"
    onLeftClicked: NetworkService.rescan()
    onRightClicked: { PopoverManager.close(); SettingsService.open("wifi") }
  }

  // A row grows its password field underneath rather than opening a second
  // popup, which this popover's own focus grab would immediately dismiss. The
  // field and the ask-for-a-key rule live in Common/PskField.
  component NetworkRow: Column {
    id: row

    required property var network

    // esc, a click outside, or another module's popover: the field goes away
    // and NetworkManager is never told anything.
    Connections {
      target: root
      function onOpenChanged() { if (!root.open) psk.collapse() }
    }

    ListRow {
      width: row.width
      implicitHeight: 32
      inset: 10
      leadingSize: 14
      titleSize: 11
      titleWeight: 500
      titleColor: Theme.alpha(Theme.text, 0.8)
      title: row.network.stateChanging ? `${row.network.name} · connecting…` : row.network.name

      leading: SignalArcs { size: 14; strength: row.network.signalStrength }

      onClicked: {
        // A network nobody has saved a key for cannot be joined by asking
        // NetworkManager to try: that drops the association you are on and
        // leaves a half-built autoconnect profile behind.
        if (psk.asking) psk.focusInput()
        else if (NetworkService.needsKey(row.network)) psk.ask()
        else NetworkService.connect(row.network)
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
    }
  }
}
