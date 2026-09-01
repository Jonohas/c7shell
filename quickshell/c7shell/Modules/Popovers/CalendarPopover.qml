import QtQuick
import Quickshell
import qs.Theme
import qs.Common
import qs.Services

// 1d: the clock popover — big clock, month card, notification list, dnd toggle.
GlassPopover {
  id: root

  name: "calendar"
  panelWidth: 360
  padding: 16
  gap: 14

  // The bar's clock only ticks once a minute; the dim seconds here need their
  // own, and only while the panel is on screen.
  SystemClock {
    id: clock
    precision: SystemClock.Seconds
    enabled: root.open
  }

  // Opening the list acknowledges whatever is toasting, and puts the month back
  // where it belongs after a page through last year.
  onOpenChanged: {
    if (!root.open) return
    NotifServer.unpopAll()
    month.toToday()
  }

  Item {
    width: parent.width
    implicitHeight: 26

    Text {
      id: hm
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      text: Qt.formatDateTime(clock.date, "HH:mm")
      font { family: Theme.fontMono; pixelSize: 22; weight: 700 }
      color: Theme.text
    }
    Text {
      anchors { left: hm.right; leftMargin: 4; baseline: hm.baseline }
      text: `:${Qt.formatDateTime(clock.date, "ss")}`
      font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
      color: Theme.alpha(Theme.text, 0.4)
    }
    Text {
      anchors { right: parent.right; baseline: hm.baseline }
      text: Qt.formatDateTime(clock.date, "ddd, MMM d yyyy").toLowerCase()
      font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
      color: Theme.accentSoft
    }
  }

  // Now-playing card — only in "compact" media style, where the clock pill is
  // the media signal and this dropdown is where the title, art and transport
  // live. In "full" style the standalone MediaPill and its own popover carry
  // all this, so the card would be a duplicate and stays hidden.
  Rectangle {
    width: parent.width
    visible: ShellStore.mediaPillStyle === "compact" && MprisService.hasPlayer
    implicitHeight: 30 + 20
    radius: Theme.radiusRow
    color: Theme.surface04
    border.width: 1
    border.color: Theme.hairline

    Row {
      anchors { fill: parent; margins: 10 }
      spacing: 10

      Rectangle {
        id: cardArt
        anchors.verticalCenter: parent.verticalCenter
        width: 30; height: 30
        radius: 6
        color: Theme.surface07
        clip: true

        Icon {
          anchors.centerIn: parent
          name: "music"
          size: 13
          tint: Theme.text3
        }
        Image {
          anchors.fill: parent
          source: MprisService.artUrl
          fillMode: Image.PreserveAspectCrop
          visible: status === Image.Ready
          asynchronous: true
          sourceSize: Qt.size(60, 60)
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - cardArt.width - transport.width - parent.spacing * 2
        spacing: 2

        Text {
          width: parent.width
          elide: Text.ElideRight
          text: MprisService.title || MprisService.identity
          font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
          color: Theme.text
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: MprisService.artist || MprisService.identity.toLowerCase()
          font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
          color: Theme.text3
        }
      }

      Row {
        id: transport
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        CardButton {
          icon: "skip-back"
          enabled: MprisService.canGoPrevious
          onTriggered: MprisService.previous()
        }
        CardButton {
          icon: MprisService.playing ? "pause" : "play"
          accent: true
          enabled: MprisService.canTogglePlaying
          onTriggered: MprisService.playPause()
        }
        CardButton {
          icon: "skip-forward"
          enabled: MprisService.canGoNext
          onTriggered: MprisService.next()
        }
      }
    }
  }

  // 14px glyph in a 26px hit target, the same sizing MediaPopover's transport
  // uses; the play glyph takes the accent tone, the skip glyphs the quiet one.
  component CardButton: Item {
    id: button

    property string icon
    property bool accent: false
    signal triggered()

    implicitWidth: 26
    implicitHeight: 26
    opacity: button.enabled ? 1 : 0.35

    Icon {
      anchors.centerIn: parent
      name: button.icon
      size: 14
      tint: button.accent ? Theme.accentSoft
        : buttonMouse.containsMouse ? Theme.text
        : Theme.text2
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: button.enabled
      onClicked: button.triggered()
    }
  }

  MonthGrid {
    id: month
    width: parent.width
    // Minute precision on purpose: bound to the seconds clock every cell in the
    // grid would re-test "is this today" once a second.
    today: Time.now
  }

  // -- notifications --------------------------------------------------------
  Item {
    width: parent.width
    implicitHeight: 18

    Row {
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      spacing: 5

      Text {
        text: "notifications"
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.alpha(Theme.text, 0.55)
      }
      Text {
        text: NotifServer.count
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.accentSoft
      }
    }

    Rectangle {
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      visible: NotifServer.count > 0
      implicitWidth: clearLabel.implicitWidth + 16
      implicitHeight: 18
      radius: 6
      color: clearMouse.containsMouse ? Theme.surface07 : "transparent"
      border.width: 1
      border.color: Theme.hairlineStrong

      Text {
        id: clearLabel
        anchors.centerIn: parent
        text: "clear all"
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        color: Theme.alpha(Theme.text, 0.35)
      }

      MouseArea {
        id: clearMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: NotifServer.clearAll()
      }
    }
  }

  // Capped so a backlog scrolls instead of growing a panel taller than the
  // screen.
  Flickable {
    id: feed

    width: parent.width
    visible: NotifServer.count > 0
    height: Math.min(contentHeight, 260)
    contentHeight: list.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: list
      // The Flickable, not `parent`: children are parented to contentItem,
      // whose width tracks contentWidth rather than the viewport.
      width: feed.width
      spacing: 7

      // Ids, not objects — see NotifRow. The ObjectModel is bound directly and
      // the delegate resolves its own id.
      Repeater {
        model: NotifServer.list
        NotifRow {
          required property var modelData
          required property int index
          width: list.width
          notificationId: modelData.id
          accented: index === 0
        }
      }
    }
  }

  Text {
    visible: NotifServer.count === 0
    text: "nothing new"
    font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
    color: Theme.alpha(Theme.text, 0.35)
    leftPadding: 2
  }

  Item {
    width: parent.width
    implicitHeight: 17

    Text {
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      text: "do not disturb"
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.35)
    }
    TogglePill {
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      implicitWidth: 26
      implicitHeight: 15
      checked: NotifServer.dnd
      onToggled: NotifServer.dnd = !NotifServer.dnd
    }
  }
}
