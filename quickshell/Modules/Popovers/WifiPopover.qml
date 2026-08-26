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
  Rectangle {
    width: parent.width
    visible: NetworkService.primary === "ethernet"
    implicitHeight: 46
    radius: Theme.radiusRow
    color: Theme.surface04
    border.width: 1
    border.color: Theme.hairline

    Rectangle {   // green status dot
      anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
      width: 7; height: 7; radius: 3.5
      color: Theme.success
    }
    Column {
      anchors { left: parent.left; leftMargin: 32; verticalCenter: parent.verticalCenter }
      spacing: 2
      Text {
        text: NetworkService.ethDevice?.name ?? ""
        font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
        color: Theme.text
      }
      Text {
        text: NetworkService.ip !== "" ? `connected · ${NetworkService.ip}` : "connected"
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: Theme.text2
      }
    }
  }

  // -- the link you are on --------------------------------------------------
  Rectangle {
    width: parent.width
    visible: NetworkService.connected !== null
    implicitHeight: 46
    radius: Theme.radiusRow
    color: Theme.accentFill
    border.width: 1
    border.color: Theme.accentBorder

    SignalArcs {
      id: joinedIcon
      anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
      size: 15
      tint: Theme.accentSoft
      strength: NetworkService.connected?.signalStrength ?? 0
    }

    Column {
      anchors {
        left: joinedIcon.right; leftMargin: 11
        right: joinedDbm.left; rightMargin: 8
        verticalCenter: parent.verticalCenter
      }
      spacing: 2

      Text {
        width: parent.width
        text: NetworkService.connected?.name ?? ""
        font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
        color: Theme.text
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: `connected · ${NetworkService.securityLabel(NetworkService.connected)}`
          + (NetworkService.primary === "wifi" && NetworkService.ip !== "" ? ` · ${NetworkService.ip}` : "")
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: Theme.alpha(Theme.text, 0.5)
        elide: Text.ElideRight
      }
    }

    Text {
      id: joinedDbm
      anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
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

      // The ObjectModel goes in as-is and the delegate filters: a rebuilt JS
      // array of its objects as `model` segfaults when one of them is destroyed
      // between a rescan and the next regenerate.
      Repeater {
        model: NetworkService.device ? NetworkService.device.networks : null
        NetworkRow {
          required property var modelData
          width: rows.width
          network: modelData
          visible: modelData.name !== "" && !modelData.connected
        }
      }
    }
  }

  // Radio on and nothing in range reads as a broken panel otherwise: the list
  // simply collapses and the section label sits over nothing. `others` is a
  // count here, never a Repeater model -- the rule is about models, not lengths.
  Text {
    width: parent.width
    visible: NetworkService.enabled && NetworkService.others.length === 0
    text: NetworkService.scanning ? "looking for networks" : "nothing in range"
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: Theme.text3
    topPadding: 2
    bottomPadding: 4
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

    Rectangle {
      width: row.width
      implicitHeight: 32
      radius: Theme.radiusTile
      color: rowMouse.containsMouse ? Theme.surface04 : "transparent"

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
          // A network nobody has saved a key for cannot be joined by asking
          // NetworkManager to try: that drops the association you are on and
          // leaves a half-built autoconnect profile behind.
          if (psk.asking) psk.focusInput()
          else if (NetworkService.needsKey(row.network)) psk.ask()
          else NetworkService.connect(row.network)
        }
      }

      SignalArcs {
        id: arcs
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        size: 14
        strength: row.network.signalStrength
      }

      Text {
        anchors {
          left: arcs.right; leftMargin: 11
          right: trailing.left; rightMargin: 8
          verticalCenter: parent.verticalCenter
        }
        text: row.network.stateChanging ? `${row.network.name} · connecting…` : row.network.name
        font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
        color: Theme.alpha(Theme.text, 0.8)
        elide: Text.ElideRight
      }

      Row {
        id: trailing
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 8

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
    }

    PskField {
      id: psk
      width: row.width
      network: row.network
    }
  }
}
