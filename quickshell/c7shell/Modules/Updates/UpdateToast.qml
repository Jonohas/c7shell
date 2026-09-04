import QtQuick
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
// The shadow, the glass and the countdown are ToastCard's.
ToastCard {
  id: root

  property string monitor: ""

  readonly property var result: UpdatesService.result
  readonly property bool escalating: UpdatesService.needsReview

  // The escalated form waits for an answer, so it does not time out.
  life: root.escalating ? 0 : 4000
  onTimeout: root.shown = false
  cardHeight: content.implicitHeight + 20

  Connections {
    target: UpdatesService
    function onFinished(ok) {
      // A failure opens the wizard instead; there is nothing a four-second
      // card can usefully say about a dependency conflict.
      if (!ok) return
      root.monitor = Hyprland.focusedMonitor?.name ?? ""
      root.shown = true
      // A second run finishing while the card is still up leaves `shown` true.
      root.kick()
    }
  }

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

      ToastAction {
        label: "review now"
        accent: true
        onTriggered: {
          root.shown = false
          UpdatesService.openWizard("review")
        }
      }
      ToastSeparator {}
      // Parked, not dismissed: settings → system keeps it, and the bar keeps
      // saying so until it is resolved.
      ToastAction { label: "later"; onTriggered: root.shown = false }
    }

    Row {
      spacing: 0
      visible: !root.escalating

      ToastAction { label: "log"; onTriggered: UpdatesService.openLog() }
    }
  }
}
