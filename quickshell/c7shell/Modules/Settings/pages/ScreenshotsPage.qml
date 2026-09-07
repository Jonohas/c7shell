import QtQuick
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings

// What happens to a capture after the shutter. One choice so far, and the one
// that decides whether the rest of the editor is ever seen.
SettingsPage {
  id: root

  title: "Screenshots"
  subtitle: "where a capture goes once it has been taken"

  Column {
    width: parent.width
    spacing: 8

    SectionHeading { width: parent.width; text: "after the shutter"; rule: false }

    SettingsCard {
      width: parent.width
      padV: 0
      padH: 0
      spacing: 0

      SettingsListRow {
        width: parent.width
        divider: false
        title: "capture opens in"
        subtitle: ShellStore.screenshotAction === "annotate"
          // Says what ↵ does, because the worry with the editor in the way is
          // that the clipboard is now two steps off. It is one key.
          ? "the annotate editor · ↵ there copies and saves"
          : "the clipboard, with nothing in between"

        Segmented {
          anchors.verticalCenter: parent.verticalCenter
          options: [
            { value: "annotate", label: "editor" },
            { value: "clipboard", label: "clipboard" }
          ]
          value: ShellStore.screenshotAction
          onPicked: v => ShellStore.values.screenshotAction = v
        }
      }
    }

    Text {
      width: parent.width
      text: "Either way the PNG is written to ~/Pictures/Screenshots. The editor "
        + "saves what you drew beside the original rather than over it, so the "
        + "capture as it was taken is always still there."
      wrapMode: Text.WordWrap
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3
    }
  }
}
