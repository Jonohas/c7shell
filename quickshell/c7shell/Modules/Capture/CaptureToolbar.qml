import QtQuick
import QtQuick.Effects
import qs.Theme
import qs.Common

// The bottom-centre bar of mockups 5a / 5b. Holds no state of its own: every
// chip reads and writes the overlay it was handed.
GlassPanel {
  id: bar

  required property var overlay

  implicitWidth: row.implicitWidth + 12
  implicitHeight: row.implicitHeight + 12
  radius: Theme.radiusPanel
  glassAlpha: Theme.glassAlphaPanel

  RectangularShadow {
    anchors.fill: parent
    radius: bar.radius
    color: Theme.panelShadowColor
    offset.y: 16
    blur: 40
    z: -1
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 4

    Rectangle {   // shot | rec segmented control
      anchors.verticalCenter: parent.verticalCenter
      width: segments.implicitWidth + 6
      height: segments.implicitHeight + 6
      radius: Theme.radiusRow
      color: Theme.surface07

      Row {
        id: segments
        anchors.centerIn: parent
        spacing: 2

        Segment {
          label: "shot"
          active: bar.overlay.mode === "shot"
          onClicked: bar.overlay.mode = "shot"
        }
        Segment {
          label: "rec"
          active: bar.overlay.mode === "rec"
          onClicked: bar.overlay.mode = "rec"
        }
      }
    }

    Item { width: 2; height: 1 }

    Chip {
      icon: "scan"; label: "region"
      active: bar.overlay.target === "region"
      onClicked: bar.setTarget("region")
    }
    Chip {
      icon: "app-window"; label: "window"
      active: bar.overlay.target === "window"
      onClicked: bar.setTarget("window")
    }
    Chip {
      icon: "monitor"; label: "screen"
      active: bar.overlay.target === "screen"
      onClicked: bar.setTarget("screen")
    }
    Chip {
      icon: "screens"; label: "all screens"
      active: bar.overlay.target === "all"
      onClicked: bar.setTarget("all")
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 1; height: 18
      color: Theme.hairlineStrong
    }

    Chip {   // 5a extras
      icon: "timer"; label: "3s"
      visible: bar.overlay.mode === "shot"
      active: bar.overlay.delayed
      onClicked: bar.overlay.delayed = !bar.overlay.delayed
    }
    Chip {
      label: "copy"
      visible: bar.overlay.mode === "shot"
      active: bar.overlay.copyToClipboard
      onClicked: bar.overlay.copyToClipboard = !bar.overlay.copyToClipboard
    }

    Chip {   // 5b extras
      icon: "mic"; label: "mic"
      visible: bar.overlay.mode === "rec"
      active: bar.overlay.mic
      // wf-recorder captures one audio device, so these two are a three-state
      // choice: mic, system audio, or silence.
      onClicked: {
        bar.overlay.mic = !bar.overlay.mic
        if (bar.overlay.mic) bar.overlay.sysAudio = false
      }
    }
    Chip {
      label: "sys audio"
      visible: bar.overlay.mode === "rec"
      active: bar.overlay.sysAudio
      onClicked: {
        bar.overlay.sysAudio = !bar.overlay.sysAudio
        if (bar.overlay.sysAudio) bar.overlay.mic = false
      }
    }
    Chip {
      label: "60fps"
      visible: bar.overlay.mode === "rec"
      active: bar.overlay.fps60
      onClicked: bar.overlay.fps60 = !bar.overlay.fps60
    }

    Rectangle {   // capture / start
      id: action
      anchors.verticalCenter: parent.verticalCenter
      width: actionRow.implicitWidth + 28
      height: 28
      radius: Theme.radiusChip
      color: Theme.accent

      RectangularShadow {
        anchors.fill: parent
        radius: action.radius
        color: Theme.alpha(Theme.accent, 0.4)
        offset: Qt.vector2d(0, 0)
        blur: 16
        z: -1
      }

      Row {
        id: actionRow
        anchors.centerIn: parent
        spacing: 7

        Rectangle {   // the record dot, drawn: JetBrains Mono has no ● and Text
          anchors.verticalCenter: parent.verticalCenter   // would fall back to
          visible: bar.overlay.mode === "rec"             // the emoji font
          width: 7; height: 7; radius: 3.5
          color: Theme.text
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: bar.overlay.mode === "rec" ? "start" : "capture ↵"
          font { family: Theme.fontMono; pixelSize: 10; weight: 600 }
          color: Theme.text
        }
      }

      MouseArea { anchors.fill: parent; onClicked: bar.overlay.arm() }
    }
  }

  // Switching target rewrites the selection, because each target means a
  // different rectangle and leaving the old one on screen would lie about what
  // is going to be captured.
  function setTarget(name) {
    bar.overlay.target = name
    if (name === "screen") bar.overlay.selectWholeScreen()
    else { bar.overlay.selW = 0; bar.overlay.selH = 0 }
  }

  component Segment: Rectangle {
    id: seg
    property string label
    property bool active: false
    signal clicked()

    width: segText.implicitWidth + 22
    height: segText.implicitHeight + 10
    radius: Theme.radiusChip
    color: seg.active ? Theme.accent : "transparent"

    Text {
      id: segText
      anchors.centerIn: parent
      text: seg.label
      font { family: Theme.fontMono; pixelSize: 10; weight: seg.active ? 600 : 500 }
      color: seg.active ? Theme.text : Theme.text2
    }

    MouseArea { anchors.fill: parent; onClicked: seg.clicked() }
  }

  component Chip: Rectangle {
    id: chip
    property string icon: ""
    property string label
    property bool active: false
    signal clicked()

    anchors.verticalCenter: parent.verticalCenter
    width: chipRow.implicitWidth + 24
    height: chipRow.implicitHeight + 12
    radius: Theme.radiusChip
    color: chip.active ? Theme.accentFill
      : chipHover.containsMouse ? Theme.surface05
      : "transparent"
    border.width: chip.active ? 1 : 0
    border.color: Theme.accentBorder

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: 7

      Icon {
        anchors.verticalCenter: parent.verticalCenter
        visible: chip.icon !== ""
        name: chip.icon
        size: 12
        tint: chip.active ? Theme.accentSoft : Theme.text2
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.label
        font { family: Theme.fontMono; pixelSize: 10; weight: chip.active ? 600 : 500 }
        color: chip.active ? Theme.text : Theme.text2
      }
    }

    MouseArea {
      id: chipHover
      anchors.fill: parent
      hoverEnabled: true
      onClicked: chip.clicked()
    }
  }
}
