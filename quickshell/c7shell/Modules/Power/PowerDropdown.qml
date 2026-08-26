import QtQuick
import Quickshell
import qs.Theme
import qs.Common
import qs.Services

// Mockup 3a. One instance in shell.qml, anchored to whichever bar's power
// button opened it; PopoverManager keeps it exclusive with the popovers, and
// PopupSurface owns the window, the grab, the mask and the shadow.
PopupSurface {
  id: root

  open: PopoverManager.current === "power"
  anchorItem: PopoverManager.anchorItem

  // Room for the drop shadow inside the popup window. Kept small on purpose:
  // the power button sits ~20px from the screen edge, and a wider window would
  // be slid inwards by the compositor's popup adjustment, which would break the
  // alignment with the button. The shadow tail is clipped at the gutter, where
  // it is already almost transparent.
  readonly property int gutter: 16

  gutterX: root.gutter
  gutterTop: root.gutter
  gutterBottom: root.gutter
  panelWidth: 232
  panelHeight: layout.implicitHeight + 16
  shadowOffset: 10
  shadowBlur: 40

  anchor.rect.x: (root.lastAnchor?.width ?? 0) + root.gutter
  anchor.rect.y: (root.lastAnchor?.height ?? 0) + 8 - root.gutter
  anchor.gravity: Edges.Bottom | Edges.Left

  onOpenChanged: if (root.open) shutdownRow.focusHold()

  Column {
    id: layout
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
    spacing: 2

    Item {   // header: identity + uptime
      width: parent.width
      implicitHeight: identity.implicitHeight + 14

      Column {
        id: identity
        anchors {
          left: parent.left; right: parent.right; top: parent.top
          leftMargin: 10; rightMargin: 10; topMargin: 6
        }
        spacing: 2

        Text {
          width: parent.width
          text: SystemInfo.userHost
          font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
          color: Theme.text
          elide: Text.ElideRight
        }
        Text {
          text: SystemInfo.uptimeText
          font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
          color: Theme.text3
        }
      }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.hairline }
    Item { width: 1; height: 4 }

    PowerRow { icon: "lock"; label: "lock"; hint: "super+l"; onTriggered: root.run(PowerActions.lock) }
    PowerRow { icon: "log-out"; label: "logout"; onTriggered: root.run(PowerActions.logout) }
    PowerRow { icon: "moon"; label: "suspend"; onTriggered: root.run(PowerActions.suspend) }

    Item { width: 1; height: 4 }
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - 16
      height: 1
      color: Theme.hairline
    }
    Item { width: 1; height: 4 }

    PowerRow {
      icon: "rotate-ccw"; label: "reboot"; destructive: true
      onTriggered: root.run(PowerActions.reboot)
    }
    PowerRow {
      id: shutdownRow
      icon: "power"; label: "shutdown"; destructive: true
      onTriggered: root.run(PowerActions.shutdown)
    }
  }

  function run(action) {
    PopoverManager.close()
    action()
  }

  // A row is either a plain click (lock / logout / suspend) or a hold-to-confirm
  // (reboot / shutdown) -- the crimson tint and the "hold ↵" hint mark which.
  component PowerRow: Rectangle {
    id: row

    property string icon
    property string label
    property string hint: ""
    property bool destructive: false
    signal triggered()

    function focusHold() { if (row.destructive) hold.forceActiveFocus() }

    width: parent.width
    height: 32
    radius: Theme.radiusChip

    color: row.destructive ? Theme.accentFill
      : click.containsMouse ? Theme.surface05
      : "transparent"
    border.width: row.destructive ? 1 : 0
    border.color: Theme.accentBorder

    // The sweep only. Its MouseArea fills the row, and the label above it has
    // none of its own, so presses reach it through the content.
    HoldButton {
      id: hold
      anchors.fill: parent
      fillRadius: row.radius
      visible: row.destructive
      // `open`, not this item's visibility and not the window's: dismissing the
      // dropdown leaves every Item in it `visible` and focused, and the window
      // itself stays mapped for the fade. This is the only binding that drops
      // the moment a hold is abandoned.
      live: root.open
      onHeld: row.triggered()
    }

    Row {
      anchors {
        left: parent.left; right: parent.right
        leftMargin: 10; rightMargin: 10
        verticalCenter: parent.verticalCenter
      }
      spacing: 11

      Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: row.icon
        size: 13
        tint: row.destructive ? Theme.accentSoft : Theme.alpha(Theme.text, 0.75)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 13 - 11 * 2 - hintText.width
        text: row.label
        font {
          family: Theme.fontMono
          pixelSize: 11
          weight: row.destructive ? 600 : 500
        }
        color: row.destructive ? Theme.text : Theme.alpha(Theme.text, 0.85)
        elide: Text.ElideRight
      }
      Text {
        id: hintText
        anchors.verticalCenter: parent.verticalCenter
        text: row.destructive ? "hold ↵" : row.hint
        font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
        color: row.destructive ? Theme.accentSoft : Theme.text3
      }
    }

    // Topmost, but disabled on destructive rows so their presses fall through to
    // the sweep below.
    MouseArea {
      id: click
      anchors.fill: parent
      hoverEnabled: true
      enabled: !row.destructive
      onClicked: row.triggered()
    }
  }
}
