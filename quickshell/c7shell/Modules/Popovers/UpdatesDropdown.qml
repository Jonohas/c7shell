pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Updates

// 12a / 12b·1: the whole merged flow's front door.
//
// The dry run has already happened by the time this opens, so it never has to
// say "checking, come back". It knows which of two things it is:
//
//   nothing needs a decision -> it does the update itself, in place, one click
//   something does           -> the same button opens the wizard
//
// The second state below is the first one continuing: the panel becomes the
// progress view rather than handing off to a window, and closing it does not
// stop anything.
GlassPopover {
  id: root

  name: "updates"
  panelWidth: 318

  readonly property bool runningHere: UpdatesService.running

  // The orphan offer, unfolded in place. Same rule as the update itself: this
  // panel does what it can do here, and a window is only for what genuinely
  // needs one.
  property bool cleaning: false
  // Folded again on close: the next open is the summary, not wherever the
  // last one was left.
  onOpenChanged: if (!root.open) root.cleaning = false

  // -- header ------------------------------------------------------------------
  Item {
    width: parent.width
    height: 22
    visible: !root.runningHere

    Text {
      id: title
      anchors { left: parent.left; top: parent.top }
      text: "updates"
      font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
      color: Theme.text
    }
    Text {
      anchors { left: title.right; leftMargin: 7; baseline: title.baseline }
      text: `${UpdatesService.total}`
      font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
      color: Theme.accentSoft
    }

    Text {
      anchors { right: refresh.left; rightMargin: 8; verticalCenter: title.verticalCenter }
      text: UpdatesService.checking ? "checking…" : UpdatesService.agoText()
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3
    }

    Item {
      id: refresh
      anchors { right: parent.right; verticalCenter: title.verticalCenter }
      width: 14; height: 14

      Icon {
        anchors.fill: parent
        name: "refresh"
        size: 14
        tint: refreshHover.hovered ? Theme.text : Theme.text3
        // The dry run is the slow part, not the spin; showing it turning is
        // the only thing separating "nothing happened" from "nothing to do".
        RotationAnimator on rotation {
          from: 0; to: 360; duration: 1400
          loops: Animation.Infinite
          running: UpdatesService.checking
        }
      }

      HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: UpdatesService.refresh() }
    }
  }

  // -- verdict -----------------------------------------------------------------
  Column {
    width: parent.width
    spacing: 2
    visible: !root.runningHere && UpdatesService.clean && UpdatesService.checkError === ""

    Text {
      text: UpdatesService.total > 0 ? "nothing needs a decision" : "up to date"
      font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
      color: Theme.success
    }
    Text {
      visible: UpdatesService.total > 0
      text: "no kernel, no replacements, no new keys"
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3
    }
  }

  DecisionStrip {
    visible: !root.runningHere && !UpdatesService.clean
    decisions: UpdatesService.decisions
  }

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    visible: !root.runningHere && UpdatesService.checkError !== ""
    text: UpdatesService.checkError
    font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
    color: Theme.accentSoft
  }

  // -- the three source cards ---------------------------------------------------
  Column {
    width: parent.width
    spacing: 6
    visible: !root.runningHere && UpdatesService.total > 0

    Repeater {
      model: UpdatesService.sources

      SourceCard {
        required property var modelData
        width: parent.width
        source: modelData
        // Open on the clean path, where the list is the content; closed on the
        // escalated one, where the decisions above it are.
        expanded: UpdatesService.clean
      }
    }
  }

  // -- the one button ------------------------------------------------------------
  UpdateButton {
    visible: !root.runningHere && UpdatesService.total > 0
    label: UpdatesService.clean ? "update" : "review & update →"
    trailing: UpdatesService.clean ? UpdatesService.humanSize(UpdatesService.size) : ""
    enabled: !UpdatesService.checking
    onTriggered: {
      if (UpdatesService.clean) {
        // Stays here. No window, no step counter -- the panel below becomes
        // the progress view and the popover is free to be closed over it.
        UpdatesService.apply()
      } else {
        PopoverManager.close()
        UpdatesService.openWizard("approve")
      }
    }
  }

  // Nothing pending, and nothing parked either.
  Text {
    width: parent.width
    visible: !root.runningHere && UpdatesService.total === 0
             && UpdatesService.pacnews.length === 0
             && UpdatesService.orphans.length === 0
    text: "everything is current"
    font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
    color: Theme.textDisabled
  }

  // Work parked by "later" on an earlier toast. It lives in settings, and this
  // is the reminder that it does.
  Item {
    width: parent.width
    height: 15
    visible: !root.runningHere && UpdatesService.pacnews.length > 0

    Text {
      anchors.left: parent.left
      text: `${UpdatesService.pacnews.length} config file${UpdatesService.pacnews.length === 1 ? "" : "s"} to review`
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.warning
    }
    Text {
      anchors.right: parent.right
      text: "review →"
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3

      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler {
        onTapped: {
          PopoverManager.close()
          UpdatesService.openWizard("review")
        }
      }
    }
  }

  // Packages nothing depends on any more. Not amber and not a decision: an
  // orphan is disk, not a broken config, and the flow is still clean with a
  // dozen of them sitting there. It is offered, and that is all.
  Item {
    width: parent.width
    height: 15
    visible: !root.runningHere && UpdatesService.orphans.length > 0

    Text {
      anchors.left: parent.left
      text: `${UpdatesService.orphans.length} package${UpdatesService.orphans.length === 1 ? "" : "s"} nothing needs`
          + (UpdatesService.orphanSize > 0
             ? ` · ${UpdatesService.humanSize(UpdatesService.orphanSize)}` : "")
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3
    }
    Text {
      anchors.right: parent.right
      text: root.cleaning ? "hide" : "clean up →"
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3

      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: root.cleaning = !root.cleaning }
    }
  }

  OrphanCard {
    width: parent.width
    visible: !root.runningHere && root.cleaning && UpdatesService.orphans.length > 0
    // Folded away, not resolved: the next dry run finds them again, and the
    // list itself is left alone so settings → system still has it.
    onDismissed: root.cleaning = false
  }

  // -- 12a · 2, running in place ---------------------------------------------------
  RunView {
    width: parent.width
    visible: root.runningHere
    logLines: 4
  }
}
