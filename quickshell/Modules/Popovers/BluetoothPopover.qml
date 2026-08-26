import QtQuick
import Quickshell.Bluetooth
import qs.Theme
import qs.Common
import qs.Services

// 1f: adapter toggle, connected devices as cards with their battery, and
// whatever the scan turns up underneath. BlueZ lives in BluetoothService.
GlassPopover {
  id: root

  name: "bluetooth"
  panelWidth: 320
  gap: 10

  // Discovery follows the panel: on while it is open, off the moment it closes.
  onOpenChanged: BluetoothService.wantScan = root.open

  Item {
    width: parent.width
    implicitHeight: 17

    Text {
      anchors { left: parent.left; right: adapterState.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
      text: "bluetooth"
      font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
      color: Theme.text
    }
    Text {
      id: adapterState
      anchors { right: toggle.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
      text: BluetoothService.adapter?.discoverable ? "discoverable" : (BluetoothService.adapter?.name ?? "no adapter")
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.35)
    }
    TogglePill {
      id: toggle
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      checked: BluetoothService.enabled
      enabled: BluetoothService.adapter !== null
      onToggled: BluetoothService.setEnabled(!BluetoothService.enabled)
    }
  }

  // -- connected ------------------------------------------------------------
  Column {
    width: parent.width
    spacing: 8

    Repeater {
      model: Bluetooth.devices
      DeviceCard {
        required property var modelData
        width: parent.width
        device: modelData
        visible: modelData.connected
        // Matching the mock: the first card carries the crimson tint.
        highlighted: BluetoothService.connectedDevices.length > 0
          && BluetoothService.connectedDevices[0] === modelData
      }
    }
  }

  Row {
    spacing: 7

    SectionLabel {
      anchors.verticalCenter: parent.verticalCenter
      text: BluetoothService.enabled ? "nearby" : "bluetooth is off"
    }
    Spinner {
      anchors.verticalCenter: parent.verticalCenter
      visible: BluetoothService.discovering
    }
  }

  // Capped so a room full of discoverable devices scrolls instead of growing a
  // panel taller than the screen. Whole rows only: the old 210px cap sliced the
  // seventh row in half at the card's edge, which reads as the list spilling out
  // of the panel rather than as something to scroll.
  Flickable {
    id: list

    readonly property int rowHeight: 32
    readonly property int maxRows: 6

    width: parent.width
    height: Math.min(contentHeight, list.rowHeight * list.maxRows)
    contentHeight: rows.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    visible: BluetoothService.enabled

    Column {
      id: rows
      // The Flickable, not `parent`: children are parented to contentItem,
      // whose width tracks contentWidth rather than the viewport.
      width: list.width

      // The ObjectModel is bound directly and filtered in the delegate: a
      // rebuilt JS array of its objects as `model` segfaults when a device
      // disappears mid-regenerate, which a scan does constantly.
      Repeater {
        model: Bluetooth.devices
        NearbyRow {
          required property var modelData
          width: rows.width
          device: modelData
          visible: !modelData.connected
        }
      }
    }
  }

  PopoverFooter {
    width: parent.width
    leftIcon: "refresh"
    leftText: BluetoothService.discovering ? "scanning" : "scan"
    rightText: "bluetooth settings →"
    onLeftClicked: BluetoothService.scan()
    onRightClicked: { PopoverManager.close(); SettingsService.open("bluetooth") }
  }

  component DeviceCard: Rectangle {
    id: card

    required property var device
    property bool highlighted: false

    readonly property int battery: BluetoothService.batteryPercent(card.device)

    implicitHeight: 46
    radius: Theme.radiusRow
    color: card.highlighted ? Theme.accentFill : Theme.surface04
    border.width: 1
    border.color: card.highlighted ? Theme.accentBorder : Theme.hairline

    MouseArea {
      anchors.fill: parent
      onClicked: BluetoothService.activate(card.device)
    }

    Icon {
      id: glyph
      anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
      name: "bluetooth"
      size: 13
      tint: card.highlighted ? Theme.accentSoft : Theme.alpha(Theme.text, 0.6)
    }

    Column {
      anchors {
        left: glyph.right; leftMargin: 11
        right: batteryBox.left; rightMargin: 8
        verticalCenter: parent.verticalCenter
      }
      spacing: 2

      Text {
        width: parent.width
        text: BluetoothService.label(card.device)
        font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
        color: card.highlighted ? Theme.text : Theme.alpha(Theme.text, 0.85)
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: BluetoothService.subtitle(card.device)
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: Theme.alpha(Theme.text, 0.5)
        elide: Text.ElideRight
      }
    }

    // "▮ 80%" — U+25AE is not in JetBrains Mono, so the bar is drawn.
    Row {
      id: batteryBox
      anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
      spacing: 5
      visible: card.battery >= 0

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: 9
        radius: 1
        color: card.highlighted ? Theme.accentSoft : Theme.alpha(Theme.text, 0.45)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: `${card.battery}%`
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        color: card.highlighted ? Theme.accentSoft : Theme.alpha(Theme.text, 0.45)
      }
    }
  }

  component NearbyRow: Rectangle {
    id: near

    required property var device

    readonly property bool anonymous: !BluetoothService.named(near.device)
    // Why the last pairing attempt on this device failed, "" if none did.
    readonly property string error: BluetoothService.pairError(near.device)

    implicitHeight: list.rowHeight
    radius: Theme.radiusTile
    color: nearMouse.containsMouse ? Theme.surface04 : "transparent"

    MouseArea {
      id: nearMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: BluetoothService.activate(near.device)
    }

    Text {
      anchors {
        left: parent.left; leftMargin: 10
        right: action.left; rightMargin: 8
        verticalCenter: parent.verticalCenter
      }
      text: BluetoothService.label(near.device)
      font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
      color: Theme.alpha(Theme.text, near.anonymous ? 0.5 : 0.8)
      elide: Text.ElideRight
    }

    Text {
      id: action
      anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
      text: near.error !== "" ? near.error
        : near.device.pairing ? "pairing…"
        : near.device.paired || near.device.bonded ? "connect"
        : "pair"
      font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
      color: near.error !== "" ? Theme.accentSoft
        : near.anonymous ? Theme.alpha(Theme.text, 0.3) : Theme.accentSoft
    }
  }
}
