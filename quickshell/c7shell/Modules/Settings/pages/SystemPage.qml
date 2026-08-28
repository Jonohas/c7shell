pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings
import qs.Modules.Updates

// Where "later" parks things.
//
// The toast at the end of a run offers "review now" or "later", and "later"
// has to mean somewhere -- otherwise it means "forget", and a config file the
// package manager could not write is not something a desktop should quietly
// forget. This is that somewhere, and the amber dot on the bar's update badge
// is the pointer to it.
SettingsPage {
  id: root

  title: "System"
  subtitle: "updates · configs to review"

  // -- updates ---------------------------------------------------------------
  SettingsCard {
    width: parent.width
    spacing: 8

    Item {
      width: parent.width
      height: 30

      Column {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        spacing: 2

        Text {
          text: UpdatesService.running ? "updating"
              : UpdatesService.total > 0 ? `${UpdatesService.total} updates pending`
              : "up to date"
          font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
          color: Theme.text
        }
        Text {
          text: UpdatesService.checking ? "checking…" : UpdatesService.agoText()
          font { family: Theme.fontMono; pixelSize: 9.5; weight: 400 }
          color: Theme.text3
        }
      }

      ActionChip {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: UpdatesService.checking ? "checking…" : "check now"
        accented: false
        onTriggered: UpdatesService.refresh()
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      visible: UpdatesService.total > 0
      text: UpdatesService.clean
        ? "nothing needs a decision — the bar's badge will do the whole update in place"
        : `${UpdatesService.decisions.length} things need a decision — the badge opens the review window`
      font { family: Theme.fontMono; pixelSize: 9.5; weight: 400 }
      color: UpdatesService.clean ? Theme.text3 : Theme.accentSoft
    }
  }

  // -- parked reviews ---------------------------------------------------------
  SectionLabel {
    text: "configs to review"
    visible: UpdatesService.pacnews.length > 0
  }

  Column {
    width: parent.width
    spacing: 8
    visible: UpdatesService.pacnews.length > 0

    Repeater {
      model: UpdatesService.pacnews
      PacnewRow {
        required property var modelData
        width: parent.width
        file: modelData
      }
    }
  }

  Text {
    width: parent.width
    visible: UpdatesService.pacnews.length === 0
    text: "no config files waiting"
    font { family: Theme.fontMono; pixelSize: 9.5; weight: 400 }
    color: Theme.textDisabled
  }

  // -- pending reboot ---------------------------------------------------------
  SettingsCard {
    width: parent.width
    visible: UpdatesService.rebootRequired

    Item {
      width: parent.width
      height: 26

      Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "a kernel update is waiting on a reboot"
        font { family: Theme.fontMono; pixelSize: 10.5; weight: 400 }
        color: Theme.text2
      }
      ActionChip {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: "reboot now"
        onTriggered: UpdatesService.reboot()
      }
    }
  }
}
