import QtQuick
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
// The shadow, the glass and the countdown are ToastCard's -- which also means
// hovering now holds this card open, as it always has for the two above it.
ToastCard {
  id: root

  property string profileKey: ""
  property real seconds: 0
  property real wasSeconds: 0

  readonly property var profile: PowerStore.profileFor(root.profileKey)

  life: 3000
  onTimeout: root.shown = false
  cardHeight: 50

  Connections {
    target: TunedService
    function onSwitched(key, seconds, wasSeconds) {
      root.profileKey = key
      root.seconds = seconds
      root.wasSeconds = wasSeconds
      root.shown = true
      // A second switch while the card is still up leaves `shown` true, so the
      // countdown needs restarting by hand.
      root.kick()
    }
  }

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
