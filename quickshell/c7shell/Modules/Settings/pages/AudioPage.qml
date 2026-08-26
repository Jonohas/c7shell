pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Popovers
import qs.Modules.Settings

// The full-size 1g: the same Pipewire nodes as the popover, with output and
// input device lists split apart instead of stacked in one picker. Every node
// filter and the volume write live in AudioService, shared with the popover.
SettingsPage {
  id: root

  title: "Audio"
  subtitle: "output · input · per-app mixer"

  // -- levels ----------------------------------------------------------------
  SettingsCard {
    width: parent.width
    spacing: 10

    LevelRow {
      width: parent.width
      node: AudioService.output
      prefix: "output"
      icon: AudioService.output?.audio?.muted ? "volume-x" : "volume-2"
    }
    CrimsonSlider {
      width: parent.width
      value: AudioService.output?.audio?.volume ?? 0
      onMoved: v => AudioService.setVolume(AudioService.output, v)
    }
    LevelRow {
      width: parent.width
      node: AudioService.input
      prefix: "input"
      icon: "mic"
    }
    CrimsonSlider {
      width: parent.width
      softFill: true
      value: AudioService.input?.audio?.volume ?? 0
      onMoved: v => AudioService.setVolume(AudioService.input, v)
    }
  }

  // -- devices ---------------------------------------------------------------
  SectionLabel { text: "output devices" }

  SettingsCard {
    width: parent.width
    padH: 4
    spacing: 2

    // The ObjectModel is bound directly and filtered in the delegate: a
    // rebuilt JS array of its objects as `model` segfaults when one is
    // destroyed mid-regenerate.
    Repeater {
      model: Pipewire.nodes

      DeviceRow {
        required property var modelData
        width: parent.width
        node: modelData
        visible: !modelData.isStream && modelData.audio && modelData.isSink
        active: modelData === AudioService.output
        onClicked: Pipewire.preferredDefaultAudioSink = modelData
      }
    }
  }

  SectionLabel { text: "input devices" }

  SettingsCard {
    width: parent.width
    padH: 4
    spacing: 2

    Repeater {
      model: Pipewire.nodes

      DeviceRow {
        required property var modelData
        width: parent.width
        node: modelData
        visible: !modelData.isStream && modelData.audio && !modelData.isSink
        active: modelData === AudioService.input
        onClicked: Pipewire.preferredDefaultAudioSource = modelData
      }
    }
  }

  // -- per-app mixer ---------------------------------------------------------
  SectionLabel {
    text: "apps"
    visible: AudioService.streams.length > 0
  }

  SettingsCard {
    width: parent.width
    visible: AudioService.streams.length > 0
    spacing: 12

    Repeater {
      model: Pipewire.nodes

      AppStreamRow {
        required property var modelData
        width: parent.width
        node: modelData
        visible: modelData.isStream && modelData.audio && modelData.isSink
      }
    }
  }

  // -- delegates -------------------------------------------------------------

  component DeviceRow: SettingsRow {
    id: device

    required property var node

    implicitHeight: 34
    leadingSize: 6
    title: AudioService.label(device.node)
    // The 6px crimson dot the mock marks the current device with.
    leading: Rectangle {
      width: 6
      height: 6
      radius: 3
      color: device.active ? Theme.accent : Theme.alpha(Theme.text, 0.2)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: device.active
      text: "default"
      font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
      color: Theme.accentSoft
    }
  }
}
