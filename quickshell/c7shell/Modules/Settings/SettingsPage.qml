import QtQuick
import qs.Theme

// Page frame: 15/700 Space Grotesk title + 10/.4 subtitle, then the page's own
// cards in a 14px-gapped column that scrolls once it outgrows the window.
// Page names are the one place the shell is not lowercase (spec §4).
Item {
  id: root

  required property string title
  property string subtitle: ""
  default property alias content: body.data

  // A status chip that belongs to the page as a whole rather than to any card
  // on it -- the power page's "tuned 2.26 · active". Baseline-aligned with the
  // subtitle, so the title still owns the top line on its own.
  property alias headerTrailing: headerSlot.data

  Row {
    id: headerSlot
    anchors { right: parent.right; top: parent.top; topMargin: 4 }
    spacing: 8
  }

  Column {
    id: head

    anchors {
      left: parent.left
      right: headerSlot.left
      // Only pages that actually put something up there give up the width.
      rightMargin: headerSlot.children.length > 0 ? 16 : 0
      top: parent.top
    }
    spacing: 2

    Text {
      // Space Grotesk with the mono as fallback: a missing display face would
      // otherwise drop the title to a serif default.
      text: root.title
      font { family: Theme.fontDisplay; pixelSize: 15; weight: 700 }
      color: Theme.text
    }
    Text {
      visible: root.subtitle !== ""
      text: root.subtitle
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.4)
    }
  }

  Flickable {
    id: scroll

    anchors {
      left: parent.left
      right: parent.right
      top: head.bottom
      bottom: parent.bottom
      topMargin: 14
    }
    contentHeight: body.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      // The Flickable, not `parent`: children are parented to contentItem,
      // whose width tracks contentWidth rather than the viewport.
      width: scroll.width
      spacing: 14
    }
  }
}
