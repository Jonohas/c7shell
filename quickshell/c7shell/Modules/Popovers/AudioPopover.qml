import QtQuick
import Quickshell.Services.Pipewire
import qs.Theme
import qs.Common
import qs.Services

// 1g: output/input sliders, device picker, per-app mixer. Every node filter,
// the label and the volume write live in AudioService, which the settings page
// shares -- they were written twice here and drifted.
GlassPopover {
  id: root

  name: "audio"
  panelWidth: 330

  Text {
    text: "audio"
    font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
    color: Theme.text
  }

  // -- output / input -------------------------------------------------------
  Rectangle {
    width: parent.width
    implicitHeight: levels.implicitHeight + 22
    radius: Theme.radiusRow
    color: Theme.surface04
    border.width: 1
    border.color: Theme.hairline

    Column {
      id: levels
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
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
  }

  SectionLabel { text: "output" }

  Column {
    width: parent.width
    spacing: 5

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
        onPicked: Pipewire.preferredDefaultAudioSink = modelData
      }
    }
  }

  SectionLabel { text: "input" }

  Column {
    width: parent.width
    spacing: 5

    Repeater {
      model: Pipewire.nodes
      DeviceRow {
        required property var modelData
        width: parent.width
        node: modelData
        visible: !modelData.isStream && modelData.audio && !modelData.isSink
        active: modelData === AudioService.input
        onPicked: Pipewire.preferredDefaultAudioSource = modelData
      }
    }
  }

  SectionLabel {
    text: "apps"
    visible: AudioService.streams.length > 0
  }

  Column {
    width: parent.width
    spacing: 9
    visible: AudioService.streams.length > 0

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

  PopoverFooter {
    width: parent.width
    rightText: "sound settings →"
    onRightClicked: { PopoverManager.close(); SettingsService.open("audio") }
  }

  // -- delegates ------------------------------------------------------------

  component DeviceRow: Rectangle {
    id: device

    required property var node
    required property bool active
    signal picked()

    implicitHeight: 28
    radius: Theme.radiusTile
    color: device.active ? Theme.accentFillSoft : (deviceMouse.containsMouse ? Theme.surface04 : "transparent")
    border.width: device.active ? 1 : 0
    border.color: Theme.accentBorderSoft

    MouseArea {
      id: deviceMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: device.picked()
    }

    Rectangle {
      anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
      width: 6
      height: 6
      radius: 3
      color: device.active ? Theme.accent : Theme.alpha(Theme.text, 0.2)
    }

    Text {
      anchors {
        left: parent.left; leftMargin: 26
        right: parent.right; rightMargin: 10
        verticalCenter: parent.verticalCenter
      }
      text: AudioService.label(device.node)
      font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
      color: device.active ? Theme.text : Theme.alpha(Theme.text, 0.7)
      elide: Text.ElideRight
    }
  }

}
