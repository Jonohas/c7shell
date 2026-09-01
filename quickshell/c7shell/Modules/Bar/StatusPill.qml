import QtQuick
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs.Theme
import qs.Common
import qs.Services

Rectangle {
  id: root

  readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property var sink: Pipewire.defaultAudioSink
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
    // The badge is a door now, not a re-check: the dry run behind it already
    // knows whether one click is enough, so opening it is the whole point.
    // While a run is going it becomes the thin progress ring the design gives
    // a dropdown that has been closed over a running update.
    QuickSlot {
      id: updateSlot
      anchors.verticalCenter: parent.verticalCenter
      visible: UpdatesService.total > 0 || UpdatesService.running
               || UpdatesService.pacnews.length > 0
      active: PopoverManager.current === "updates"
      slotColor: UpdatesService.kernelPending ? Theme.accentFill : "transparent"
      onClicked: PopoverManager.toggle("updates", updateSlot)

      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: 13; height: 13

        Icon {
          anchors.fill: parent
          visible: !UpdatesService.running
          name: "package"; size: 13
          tint: UpdatesService.kernelPending ? Theme.accentSoft : Theme.text3
        }
        ProgressRing {
          anchors.fill: parent
          visible: UpdatesService.running
          fraction: UpdatesService.runTotal > 0
            ? UpdatesService.doneCount / UpdatesService.runTotal : 0
        }

        // Housekeeping parked by a "later": amber, and it outlives the run
        // that produced it. Overlaid on the icon rather than placed beside it,
        // so it does not push the count along.
        Rectangle {
          anchors { right: parent.right; top: parent.top; margins: -1 }
          visible: UpdatesService.pacnews.length > 0 && !UpdatesService.running
          width: 4; height: 4; radius: 2
          color: Theme.warning
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        // The count only, never a "0": the slot also stands for a parked
        // pacnew and for the seconds after a run when nothing has been
        // counted yet, and in both the icon alone is the honest badge.
        visible: !UpdatesService.running && UpdatesService.total > 0
        text: `${UpdatesService.total}`
        font { family: Theme.fontMono; pixelSize: 10; weight: 600 }
        color: UpdatesService.kernelPending ? Theme.accentSoft : Theme.text3
      }
    }
    QuickSlot {
      anchors.verticalCenter: parent.verticalCenter
      active: CaptureService.overlayOpen
      onClicked: CaptureService.toggle()
      Icon { name: "scan"; tint: CaptureService.overlayOpen ? Theme.accentSoft : Theme.text }
    }
    // Airplane mode has no popover of its own: the slot only exists while every
    // radio is off, and the one thing to do from there is come back out. It
    // sits ahead of the radio slots because it is the reason they look the way
    // they do -- and it appears however the radios went down, the Fn key
    // included, since the service derives the mode rather than storing it.
    QuickSlot {
      anchors.verticalCenter: parent.verticalCenter
      visible: AirplaneService.enabled
      slotColor: Theme.accentFill
      onClicked: AirplaneService.setEnabled(false)
      Icon { name: "plane"; tint: Theme.accentSoft }
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
    // Below the warn threshold the whole slot goes crimson-tinted, which is
    // the one state the battery widget is allowed to shout in.
    QuickSlot {
      id: batterySlot
      anchors.verticalCenter: parent.verticalCenter
      visible: BatteryService.present
      active: PopoverManager.current === "battery"
      slotColor: battery.warn ? Theme.accentFill : "transparent"
      slotBorder: battery.warn ? Theme.accentBorder : "transparent"
      onClicked: PopoverManager.toggle("battery", batterySlot)

      BatteryIndicator {
        id: battery
        anchors.verticalCenter: parent.verticalCenter
        // The tooltip stands down while the popover is up: it says a subset of
        // what the panel says, and two surfaces over one pill is one too many.
        hovered: batterySlot.hovered && PopoverManager.current !== "battery"
      }
    }
  }
}
