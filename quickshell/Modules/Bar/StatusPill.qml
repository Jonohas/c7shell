import QtQuick
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Theme
import qs.Common
import qs.Services

Rectangle {
  id: root

  readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: battery?.isLaptopBattery ?? false
  readonly property bool muted: sink?.audio?.muted ?? false

  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  implicitWidth: content.implicitWidth + 12   // slots carry their own padding now
  implicitHeight: Theme.pillHeight
  radius: Theme.pillRadius
  color: Theme.surface05

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 2   // slots carry their own padding now

    QuickSlot {
      anchors.verticalCenter: parent.verticalCenter
      visible: ScreenshareService.active
      slotColor: Theme.alpha(Theme.accent, 0.18)
      hoverColor: Theme.powerHover
      onClicked: ScreenshareService.stop()
      Icon { name: "screen-share"; tint: Theme.accentSoft }
    }
    QuickSlot {
      anchors.verticalCenter: parent.verticalCenter
      active: CaptureService.overlayOpen
      onClicked: CaptureService.toggle()
      Icon { name: "scan"; tint: CaptureService.overlayOpen ? Theme.accentSoft : Theme.text }
    }
    QuickSlot {
      id: netSlot
      anchors.verticalCenter: parent.verticalCenter
      visible: root.wifi !== null || NetworkService.ethDevice !== null
      active: PopoverManager.current === "wifi"
      slotColor: NetworkService.primary === "none" ? Theme.accentFill : "transparent"
      onClicked: PopoverManager.toggle("wifi", netSlot)

      Item {
        width: 15; height: 15
        anchors.verticalCenter: parent.verticalCenter
        Icon {
          anchors.fill: parent
          name: NetworkService.primary === "ethernet" ? "ethernet" : "wifi"
          tint: NetworkService.primary === "none" ? Theme.accentSoft : Theme.text
        }
        Text {   // ✕ badge, bottom-right, only when offline
          visible: NetworkService.primary === "none"
          anchors { right: parent.right; bottom: parent.bottom; rightMargin: -2; bottomMargin: -2 }
          text: "✕"
          font { family: Theme.fontMono; pixelSize: 7; weight: 700 }
          color: Theme.accentSoft
        }
      }
    }
    QuickSlot {
      id: btSlot
      anchors.verticalCenter: parent.verticalCenter
      visible: root.btAdapter !== null && root.btAdapter.enabled
      active: PopoverManager.current === "bluetooth"
      onClicked: PopoverManager.toggle("bluetooth", btSlot)
      Icon { name: "bluetooth"; tint: Theme.text }
    }
    QuickSlot {
      id: volSlot
      anchors.verticalCenter: parent.verticalCenter
      visible: root.sink !== null
      active: PopoverManager.current === "audio"
      onClicked: PopoverManager.toggle("audio", volSlot)
      Icon { name: root.muted ? "volume-x" : "volume-2"; tint: root.muted ? Theme.accentSoft : Theme.text }
    }
    QuickSlot {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.hasBattery
      BatteryIndicator { anchors.verticalCenter: parent.verticalCenter }
    }
  }
}
