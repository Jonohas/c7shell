import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Theme
import qs.Common
import qs.Services

// Mockup 5b, top right: what you just captured, and the three things you are
// likely to do with it. Auto-hides; the file actions run in CaptureService.
PanelWindow {
  id: win

  property string path: ""
  readonly property string filename: win.path.substring(win.path.lastIndexOf("/") + 1)

  // Room for the drop shadow inside the window; the card sits inset by it, so
  // the margins below still land the card where the mockup puts it.
  readonly property int gutter: 20

  // Latched, not bound: without an explicit screen the compositor is free to map
  // the toast on an output the capture had nothing to do with. The capture just
  // happened on the focused monitor, so that is the one the card belongs on, and
  // it must not migrate under the pointer while it is up.
  property string monitor: ""
  screen: Quickshell.screens.find(s => s.name === win.monitor) ?? null

  anchors { top: true; right: true }
  // Ignore, not a zero zone: a zero zone still respects the bar's 48px, which
  // pushed the card 48px below where the margins below place it.
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.namespace: "gambleland-toast"
  WlrLayershell.layer: WlrLayer.Overlay

  // Clear of the 38px bar (10px margin + 38px island), per the mockup: card top
  // at 60, card right edge 22 from the screen edge.
  margins { top: 40; right: 2 }

  implicitWidth: card.width + win.gutter * 2
  implicitHeight: card.height + win.gutter * 2 + 12
  mask: Region { item: card }
  visible: win.path !== ""

  // The notification stack shares this corner, and unhandled the two draw on
  // top of each other. Publish this card's bottom edge in SCREEN coordinates --
  // this window ignores the bar's exclusive zone, that one does not, so neither
  // can read the other's margins directly -- and let the stack start below it.
  // ponytail: two hosts is the actual defect; one top-right host with two card
  // types (simplify pass S5) deletes this hand-off along with ~60 lines.
  Binding {
    target: CaptureService
    property: "toastBottom"
    value: win.visible ? Math.round(win.margins.top + win.gutter + card.height) : 0
  }

  Connections {
    target: CaptureService
    function onCaptured(path) { win.show(path) }
    // The file is really in the trash now. Until this arrives the card stays up,
    // so a failed delete cannot be mistaken for a successful one.
    function onDiscarded(path) { if (path === win.path) win.path = "" }
  }
  Connections {
    target: RecordingService
    function onFinished(path) { win.show(path) }
  }

  function show(path) {
    win.monitor = Hyprland.focusedMonitor?.name ?? ""
    win.path = path
    life.restart()
  }

  Timer { id: life; interval: 6000; onTriggered: win.path = "" }

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
    x: win.gutter
    y: win.gutter
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
          source: win.path ? `file://${win.path}` : ""
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
          text: win.filename
          font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
          color: Theme.text
        }

        Row {
          spacing: 0
          ToastAction { label: "open"; accent: true; onTriggered: CaptureService.openFile(win.path) }
          Separator {}
          ToastAction { label: "folder"; onTriggered: CaptureService.openFolder(win.path) }
          Separator {}
          ToastAction {
            label: "delete"
            onTriggered: CaptureService.discard(win.path)
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
