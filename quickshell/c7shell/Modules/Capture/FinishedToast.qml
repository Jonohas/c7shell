import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import qs.Theme
import qs.Common
import qs.Services

// Mockup 5b, top right: what you just captured, and the three things you are
// likely to do with it. Auto-hides; the file actions run in CaptureService.
//
// A card, not a window: it shares the top-right host with the notification
// stack. Two windows in that corner is what drew the two cards on top of each
// other, and the hand-off that patched it needed a service property to carry
// one window's bottom edge to the other.
Item {
  id: root

  property string path: ""
  readonly property string filename: root.path.substring(root.path.lastIndexOf("/") + 1)

  // Latched, not bound: the capture just happened on the focused monitor, so
  // that is the one the card belongs on, and it must not migrate under the
  // pointer while it is up. The host reads this to place itself.
  property string monitor: ""

  visible: root.path !== ""
  implicitHeight: root.visible ? card.height : 0

  Connections {
    target: CaptureService
    function onCaptured(path) { root.show(path) }
    // The file is really in the trash now. Until this arrives the card stays up,
    // so a failed delete cannot be mistaken for a successful one.
    function onDiscarded(path) { if (path === root.path) root.path = "" }
  }
  Connections {
    target: RecordingService
    function onFinished(path) { root.show(path) }
  }

  function show(path) {
    root.monitor = Hyprland.focusedMonitor?.name ?? ""
    root.path = path
    life.restart()
  }

  Timer { id: life; interval: 6000; onTriggered: root.path = "" }

  RectangularShadow {
    anchors.fill: card
    radius: card.radius
    color: Theme.panelShadowColor
    offset.y: 12
    blur: 40
    z: -1
  }

  GlassPanel {
    id: card

    anchors { right: parent.right; top: parent.top }
    width: content.implicitWidth + 24
    height: content.implicitHeight + 18
    radius: Theme.pillRadius
    glassAlpha: Theme.glassAlphaPanel

    Row {
      id: content
      anchors.centerIn: parent
      spacing: 10

      Item {   // thumbnail, or stripes when there is nothing to show one from
        anchors.verticalCenter: parent.verticalCenter
        width: 52; height: 32
        clip: true

        Rectangle {
          anchors.fill: parent
          radius: Theme.radiusPip
          color: Theme.surface04
        }

        Item {   // 45° stripes, the mockup's placeholder
          anchors.fill: parent
          visible: thumb.status !== Image.Ready

          Repeater {
            model: 12
            Rectangle {
              required property int index
              x: index * 8 - 20
              y: -16
              width: 4
              height: 64
              rotation: 45
              color: Theme.surface07
            }
          }
        }

        Image {
          id: thumb
          anchors.fill: parent
          // Video has no decodable first frame here; the stripes stay for those.
          source: root.path ? `file://${root.path}` : ""
          sourceSize: Qt.size(104, 64)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          visible: thumb.status === Image.Ready
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
          text: root.filename
          font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
          color: Theme.text
        }

        Row {
          spacing: 0
          ToastAction { label: "open"; accent: true; onTriggered: CaptureService.openFile(root.path) }
          Separator {}
          ToastAction { label: "folder"; onTriggered: CaptureService.openFolder(root.path) }
          Separator {}
          ToastAction {
            label: "delete"
            onTriggered: CaptureService.discard(root.path)
          }
        }
      }
    }

    MouseArea {   // hovering holds the toast open while you aim at an action
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: life.stop()
      onExited: life.restart()
    }
  }

  component Separator: Text {
    text: " · "
    font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
    color: Theme.text3
  }

  component ToastAction: Text {
    id: act
    property string label
    property bool accent: false
    signal triggered()

    text: act.label
    font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
    color: act.accent ? Theme.accentSoft : Theme.text3

    MouseArea {
      anchors.fill: parent
      anchors.margins: -4
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: act.triggered()
    }
  }
}
