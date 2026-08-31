import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import qs.Theme
import qs.Common
import qs.Services

// 12a·3 and 12b·3: the end of a clean run, four seconds, top right.
//
// It has two forms and they are the same card. A run that produced nothing to
// review just says so and goes away -- that is the whole interaction, and no
// window was ever opened. A run that turned out to need a decision anyway
// escalates *here*, at the end, rather than the run having stopped in the
// middle to ask: "review now" opens the wizard at step 3 alone, "later" parks
// it in settings with a dot on the bar.
//
// A card, not a window: it shares the top-right host with the notification
// stack and the capture card. Two windows in that corner is what drew two
// cards on top of each other once already.
Item {
  id: root

  property bool shown: false
  property string monitor: ""

  readonly property var result: UpdatesService.result
  readonly property bool escalating: UpdatesService.needsReview

  visible: root.shown
  implicitHeight: root.visible ? card.height : 0

  Connections {
    target: UpdatesService
    function onFinished(ok) {
      // A failure opens the wizard instead; there is nothing a four-second
      // card can usefully say about a dependency conflict.
      if (!ok) return
      root.monitor = Hyprland.focusedMonitor?.name ?? ""
      root.shown = true
      life.restart()
    }
  }

  // The escalated form waits for an answer, so it does not time out.
  Timer { id: life; interval: 4000; onTriggered: if (!root.escalating) root.shown = false }

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
    height: content.implicitHeight + 20
    radius: Theme.radiusCard

    Column {
      id: content
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
      spacing: 5

      Row {
        spacing: 7

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 6; height: 6; radius: 3
          color: root.escalating ? Theme.warning : Theme.success
        }
        Text {
          text: root.escalating
            ? `${root.result?.updated ?? 0} updated · ${UpdatesService.pacnews.length} config${UpdatesService.pacnews.length === 1 ? "" : "s"} to review`
            : `${root.result?.updated ?? 0} packages updated`
          font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
          color: Theme.text
        }
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: root.escalating
          ? (UpdatesService.pacnews.length > 0
              ? "pacnew files appeared during the run"
              : "a kernel update is waiting on a reboot")
          : `${UpdatesService.duration(root.result?.secs)} · nothing to review`
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: Theme.text3
      }

      Row {
        spacing: 0
        visible: root.escalating

        Action {
          label: "review now"
          accent: true
          onTriggered: {
            root.shown = false
            UpdatesService.openWizard("review")
          }
        }
        Sep {}
        // Parked, not dismissed: settings → system keeps it, and the bar keeps
        // saying so until it is resolved.
        Action { label: "later"; onTriggered: root.shown = false }
      }

      Row {
        spacing: 0
        visible: !root.escalating

        Action { label: "log"; onTriggered: UpdatesService.openLog() }
      }
    }

    MouseArea {   // hovering holds it open while you aim at an action
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: life.stop()
      onExited: if (!root.escalating) life.restart()
    }
  }

  component Sep: Text {
    text: " · "
    font { family: Theme.fontMono; pixelSize: 9 }
    color: Theme.text3
  }

  component Action: Text {
    id: act
    property string label
    property bool accent: false
    signal triggered()

    text: act.label
    font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
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
