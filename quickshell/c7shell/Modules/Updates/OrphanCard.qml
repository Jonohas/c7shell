import QtQuick
import qs.Common
import qs.Theme
import qs.Services

// The packages nothing depends on any more, with the two things you can do
// about them. One component at three widths -- the 318px dropdown, the
// wizard's step 3 and settings -- for the same reason RunView is one: they are
// the same offer, and a second copy is a second set of wordings to keep in
// step.
//
// Not amber and not crimson: an orphan is disk, not a broken config and not a
// failure. It is offered, and the flow is complete whether or not it is taken.
Rectangle {
  id: root

  // "keep them" parks the offer rather than resolving it -- what that means
  // is the caller's business: the dropdown folds the section away, the wizard
  // and settings drop the list until the next dry run finds it again.
  signal dismissed()

  implicitWidth: parent ? parent.width : 340
  implicitHeight: body.implicitHeight + 18
  radius: Theme.radiusRow
  color: Theme.surface04
  border.width: 1
  border.color: Theme.hairline

  Column {
    id: body
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
    spacing: 6

    Text {
      width: parent.width
      elide: Text.ElideRight
      text: `${UpdatesService.orphans.length} package${UpdatesService.orphans.length === 1 ? "" : "s"} nothing depends on`
          + (UpdatesService.orphanSize > 0
             ? ` · ${UpdatesService.humanSize(UpdatesService.orphanSize)}` : "")
      font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
      color: Theme.text
    }

    // Spelled out, always. "12 packages" is not something to say yes to
    // unseen, and this is the only place the names appear.
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: UpdatesService.orphanNames().join(" · ")
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3
    }

    Row {
      spacing: 6

      Chip {
        text: UpdatesService.removingOrphans ? "removing…" : "remove them"
        highlight: !UpdatesService.removingOrphans
        // The polkit dialog is the slow part and it is somebody else's
        // window, so the button says what is happening rather than looking
        // dead for as long as it is up.
        enabled: !UpdatesService.removingOrphans
        onTriggered: UpdatesService.removeOrphans(UpdatesService.orphanNames())
      }
      Chip {
        text: "keep them"
        enabled: !UpdatesService.removingOrphans
        onTriggered: root.dismissed()
      }
    }
  }
}
