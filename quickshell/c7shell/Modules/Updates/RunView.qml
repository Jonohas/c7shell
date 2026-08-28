pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// The running state, shared by the dropdown (12a·2) and the wizard's step 2.
// One component because they are the same thing at two widths: a headline, the
// per-source rows, the collapsed log, a bar and abort.
//
// The log is above the bar and collapsed by default on purpose. The design's
// claim is that you never need it; leaving it one click away rather than
// absent is what makes that claim safe to make.
Column {
  id: root

  // The wizard shows the per-source rows; the 318px dropdown has no room and
  // leans on the log's last line instead.
  property bool showPhases: false
  property int logLines: 4

  spacing: 9

  readonly property real fraction:
    UpdatesService.runTotal > 0
      ? Math.min(1, UpdatesService.doneCount / UpdatesService.runTotal) : 0

  // -- headline ---------------------------------------------------------------
  Column {
    width: parent.width
    spacing: 2

    Text {
      text: UpdatesService.awaitingAuth ? "waiting for authorisation" : "updating"
      font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
      color: Theme.text
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: UpdatesService.awaitingAuth
        ? "confirm the prompt to continue"
        : `${UpdatesService.doneCount} of ${UpdatesService.runTotal}`
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3
    }
  }

  // -- per-source rows --------------------------------------------------------
  Column {
    width: parent.width
    spacing: 4
    visible: root.showPhases

    Repeater {
      model: ["pacman", "aur", "flatpak"]

      Item {
        id: phase
        required property var modelData
        readonly property var ph: UpdatesService.phases[phase.modelData] ?? null

        width: parent.width
        height: phase.visible ? 15 : 0
        visible: phase.ph !== null

        Text {
          anchors.left: parent.left
          text: phase.modelData
          font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
          color: phase.ph?.state === "failed" ? Theme.accentSoft : Theme.text2
        }
        Text {
          anchors.right: parent.right
          text: {
            const s = phase.ph?.state ?? ""
            if (s === "done") return UpdatesService.duration(phase.ph.secs)
            if (s === "failed") return "failed"
            return "running"
          }
          font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
          color: phase.ph?.state === "done" ? Theme.success
               : phase.ph?.state === "failed" ? Theme.accentSoft
               : Theme.text3
        }
      }
    }
  }

  // -- the log ----------------------------------------------------------------
  Rectangle {
    width: parent.width
    implicitHeight: log.implicitHeight + 14
    radius: Theme.radiusPip
    color: Theme.alpha("#000000", 0.28)
    border.width: 1
    border.color: Theme.hairline

    Column {
      id: log
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7 }
      spacing: 1

      Repeater {
        model: UpdatesService.lines.slice(Math.max(0, UpdatesService.lines.length - root.logLines))

        Text {
          required property string modelData
          width: log.width
          elide: Text.ElideRight
          text: modelData
          font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
          color: Theme.text3
        }
      }

      Text {
        visible: UpdatesService.lines.length === 0
        text: UpdatesService.awaitingAuth ? "…" : "starting"
        font { family: Theme.fontMono; pixelSize: 9 }
        color: Theme.textDisabled
      }
    }
  }

  // -- bar + abort ------------------------------------------------------------
  Item {
    width: parent.width
    height: 16

    Rectangle {
      id: track
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      width: parent.width - pct.width - abort.width - 22
      height: 4
      radius: 2
      color: Theme.surface10

      Rectangle {
        width: parent.width * root.fraction
        height: parent.height
        radius: parent.radius
        color: Theme.accent
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      }
    }

    Text {
      id: pct
      anchors { left: track.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
      text: `${Math.round(root.fraction * 100)}%`
      font { family: Theme.fontMono; pixelSize: 9.5; weight: 600 }
      color: Theme.text2
    }

    Text {
      id: abort
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      text: "abort"
      font { family: Theme.fontMono; pixelSize: 9.5; weight: 400 }
      color: Theme.accentSoft

      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: UpdatesService.abort() }
    }
  }

  Text {
    width: parent.width
    text: "safe to close — it keeps going"
    font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
    color: Theme.textDisabled
  }
}
