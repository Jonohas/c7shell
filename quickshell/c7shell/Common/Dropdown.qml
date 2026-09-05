pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.Theme

// The shell's one dropdown: a chip showing the current value, a popup list of
// options. QtQuick.Controls is not imported by any view here and a ComboBox
// would drag its whole style in, so this is hand-rolled from the same chip
// vocabulary Chip uses.
//
// The list is reparented to the window's contentItem. Settings pages scroll
// inside a clipping Flickable, so a popup drawn as a child of its row would be
// sliced off at the card edge. Inside the settings window there is no layer
// surface and nothing to grab — this is an ordinary QtQuick item on top of the
// window, dismissed by clicking anywhere else or pressing escape.
Item {
  id: root

  // Plain strings: every list this page needs is one ("3440x1440", "99.99").
  property var options: []
  property string current: ""
  property string placeholder: "—"
  property int maxRows: 9

  signal picked(string value)

  readonly property int rowHeight: 22
  readonly property bool opened: overlay.visible

  implicitWidth: 128
  implicitHeight: 22

  function open() {
    if (root.options.length === 0) return
    list.currentIndex = Math.max(0, root.options.indexOf(root.current))
    overlay.visible = true
    list.positionViewAtIndex(list.currentIndex, ListView.Contain)
    list.forceActiveFocus()
  }

  function close() {
    overlay.visible = false
  }

  function commit(i) {
    root.close()
    if (i >= 0 && i < root.options.length) root.picked(root.options[i])
  }

  // -- the button
  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusChip
    color: hover.containsMouse || root.opened ? Theme.surface07 : Theme.surface05
    border.width: 1
    border.color: root.opened ? Theme.accentBorder : Theme.hairlineStrong

    Text {
      anchors {
        left: parent.left; leftMargin: 9
        right: caret.left; rightMargin: 6
        verticalCenter: parent.verticalCenter
      }
      text: root.current !== "" ? root.current : root.placeholder
      elide: Text.ElideRight
      font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
      color: root.current !== "" ? Theme.text : Theme.textDisabled
    }

    // A glyph rather than an icon asset: Assets/icons has no chevron and one
    // triangle does not justify adding one.
    Text {
      id: caret
      anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
      text: "▾"
      font { family: Theme.fontMono; pixelSize: 9; weight: 500 }
      color: Theme.alpha(Theme.text, root.opened ? 0.75 : 0.4)
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      onClicked: root.opened ? root.close() : root.open()
    }
  }

  // -- the popup
  Item {
    id: overlay

    // Falls back to the row itself if this is ever used outside a Window; the
    // list is then clipped rather than missing.
    parent: root.Window.contentItem ?? root
    anchors.fill: parent
    z: 200
    visible: false

    onVisibleChanged: if (visible) overlay.place()

    function place() {
      const below = root.mapToItem(overlay, 0, root.height + 4)
      panel.x = Math.max(4, Math.min(below.x, overlay.width - panel.width - 4))
      panel.y = below.y + panel.height <= overlay.height - 4
        ? below.y
        : Math.max(4, root.mapToItem(overlay, 0, -4).y - panel.height)
    }

    MouseArea {
      anchors.fill: parent
      onPressed: root.close()
    }

    RectangularShadow {
      anchors.fill: panel
      radius: panel.radius
      blur: 34
      spread: 0
      offset.y: 10
      color: Theme.panelShadowColor
    }

    Rectangle {
      id: panel

      width: Math.max(root.width, 108)
      height: list.height + 8
      radius: Theme.radiusChip + 2
      // The settings window is opaque, so this is a solid raised surface rather
      // than glass: nothing behind it is blurred and nothing should show through.
      color: Theme.canvas
      border.width: 1
      border.color: Theme.hairlineStrong

      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.surface07
      }

      ListView {
        id: list

        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
        height: Math.min(root.options.length, root.maxRows) * root.rowHeight
        model: root.options
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationWraps: true

        Keys.onEscapePressed: root.close()
        Keys.onReturnPressed: root.commit(list.currentIndex)
        Keys.onEnterPressed: root.commit(list.currentIndex)

        delegate: Rectangle {
          required property int index
          required property string modelData

          width: list.width
          height: root.rowHeight
          radius: Theme.radiusMenuRow
          color: index === list.currentIndex ? Theme.accentFill : "transparent"
          border.width: 1
          border.color: index === list.currentIndex ? Theme.accentBorder : "transparent"

          Text {
            anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
            text: parent.modelData
            font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
            color: parent.modelData === root.current ? Theme.accentSoft : Theme.alpha(Theme.text, 0.8)
          }

          // The current value keeps a marker even when the keyboard highlight
          // has moved off it.
          Text {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            visible: parent.modelData === root.current
            text: "•"
            font { family: Theme.fontMono; pixelSize: 11; weight: 700 }
            color: Theme.accentSoft
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: list.currentIndex = parent.index
            onClicked: root.commit(parent.index)
          }
        }
      }
    }
  }
}
