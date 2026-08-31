import QtQuick
import QtQuick.Effects
import qs.Theme
import qs.Common
import qs.Services

// 17b·3: the confirmation for a profile switch the user did not click for --
// an automatic one on unplug, the drop below the threshold, or a keybind. A
// click in the popover is its own feedback and never lands here.
//
// The new estimate against the old one, because that is the whole content of
// the event: the profile name alone does not say what it bought.
//
// A card, not a window: it shares the top-right host with the notification
// stack, the capture card and the update toast.
Item {
  id: root

  property bool shown: false
  property string profileKey: ""
  property real seconds: 0
  property real wasSeconds: 0

  readonly property var profile: PowerStore.profileFor(root.profileKey)

  visible: root.shown
  implicitHeight: root.visible ? card.height : 0

  Connections {
    target: TunedService
    function onSwitched(key, seconds, wasSeconds) {
      root.profileKey = key
      root.seconds = seconds
      root.wasSeconds = wasSeconds
      root.shown = true
      life.restart()
    }
  }

  Timer { id: life; interval: 3000; onTriggered: root.shown = false }

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
    width: parent.width
    height: 50
    radius: Theme.radiusCard

    Rectangle {
      id: tile

      anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
      width: 28
      height: 28
      radius: Theme.radiusChip
      color: Theme.accentFill
      border.width: 1
      border.color: Theme.accentBorder

      Icon {
        anchors.centerIn: parent
        name: root.profile?.icon ?? "zap"
        size: 14
        tint: Theme.accentSoft
      }
    }

    Column {
      anchors {
        left: tile.right; leftMargin: 11
        right: parent.right; rightMargin: 12
        verticalCenter: parent.verticalCenter
      }
      spacing: 2

      Text {
        width: parent.width
        text: root.profile?.label ?? root.profileKey
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.text
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        // Both halves drop themselves when the machine has not given us the
        // arithmetic yet -- a first-boot toast says the profile name and stops,
        // rather than printing "≈ — · was —".
        text: {
          if (root.seconds <= 0) return "switched automatically"
          const now = `≈ ${BatteryService.duration(root.seconds)}`
          return root.wasSeconds > 0
            ? `${now} · was ${BatteryService.duration(root.wasSeconds)}` : now
        }
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: Theme.text3
        elide: Text.ElideRight
      }
    }
  }
}
