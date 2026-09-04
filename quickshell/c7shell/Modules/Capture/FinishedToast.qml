import QtQuick
import Quickshell.Hyprland
import qs.Theme
import qs.Common
import qs.Services

// Mockup 5b, top right: what you just captured, and the three things you are
// likely to do with it. Auto-hides; the file actions run in CaptureService.
//
// The shadow, the glass and the countdown are ToastCard's -- this file is the
// content and the capture-specific lifetime.
ToastCard {
  id: root

  property string path: ""
  readonly property string filename: root.path.substring(root.path.lastIndexOf("/") + 1)

  // Latched, not bound: the capture just happened on the focused monitor, so
  // that is the one the card belongs on, and it must not migrate under the
  // pointer while it is up. The host reads this to place itself.
  property string monitor: ""

  shown: root.path !== ""
  life: 6000
  onTimeout: root.path = ""

  // Shrink to fit, unlike the other cards in the stack: this one is a pill
  // around a 52px thumbnail and three words.
  cardWidth: content.implicitWidth + 24
  cardHeight: content.implicitHeight + 18

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
    // A second capture while the first card is still up leaves `shown` true,
    // so the countdown needs restarting by hand.
    root.kick()
  }

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
        ToastSeparator {}
        ToastAction { label: "folder"; onTriggered: CaptureService.openFolder(root.path) }
        ToastSeparator {}
        ToastAction {
          label: "delete"
          onTriggered: CaptureService.discard(root.path)
        }
      }
    }
  }
}
