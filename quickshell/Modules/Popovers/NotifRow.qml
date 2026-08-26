import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// One notification, drawn the same in the 1d list and in a toast — the toast
// just gets the glass background instead of a raised row on top of one.
Rectangle {
  id: root

  // A notification id, not the object: a Repeater copies its model into raw
  // QObject pointers and quickshell deletes a Notification the instant it
  // closes, leaving the copy dangling. An int cannot dangle.
  required property int notificationId
  property bool accented: false
  property bool glass: false

  readonly property var notification: NotifServer.byId(root.notificationId)
  readonly property bool alive: root.notification !== null

  // Every read below is optional-chained for the frame between a notification
  // being destroyed and its row being torn down.
  readonly property string appLabel: root.notification?.appName ?? ""
  readonly property string bodyLabel: {
    const n = root.notification
    if (!n) return ""
    return [n.summary, n.body].filter(s => s !== "").join(" — ")
  }

  visible: root.alive
  implicitHeight: Math.max(28, body.implicitHeight) + 20
  radius: root.glass ? Theme.radiusCard : Theme.radiusRow
  color: root.glass ? Theme.alpha(Theme.glassBase, Theme.glassAlphaPanel) : Theme.surface04
  border.width: 1
  border.color: Theme.hairline

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: if (root.alive) NotifServer.dismiss(root.notification)
  }

  MonogramTile {
    id: tile
    anchors { left: parent.left; leftMargin: 12; top: parent.top; topMargin: 10 }
    size: 28
    label: root.appLabel
    accented: root.accented
  }

  Column {
    id: body

    anchors {
      left: tile.right; leftMargin: 10
      right: parent.right; rightMargin: 12
      top: parent.top; topMargin: 10
    }
    spacing: 3

    Item {
      width: parent.width
      implicitHeight: 15

      Text {
        anchors { left: parent.left; right: age.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: root.appLabel
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.text
        elide: Text.ElideRight
      }
      Text {
        id: age
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: NotifServer.ago(root.notificationId, NotifServer.tick)
        font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
        color: Theme.alpha(Theme.text, 0.35)
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: root.bodyLabel
      // The server advertises markup support, so the body may contain it.
      textFormat: Text.StyledText
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      lineHeight: 1.5
      color: Theme.alpha(Theme.text, 0.55)
      wrapMode: Text.Wrap
      maximumLineCount: 3
      elide: Text.ElideRight
    }
  }
}
