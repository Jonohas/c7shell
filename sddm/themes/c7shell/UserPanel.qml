import QtQuick

// The 250px panel to the left of the card, listing the accounts sddm found.
// Shown when there is more than one to pick from, or when "switch user" asks
// for it; Up/Down moves through it from anywhere in the greeter.
GlassPanel {
  id: root

  property var users: null           // sddm's userModel
  property int currentIndex: 0
  // "other..." at the end, for a username sddm does not list (a hidden or
  // remote account). Off unless theme.conf turns it on.
  property bool allowManualLogin: false
  readonly property int manualIndex: root.users ? root.users.count : 0
  readonly property bool manualSelected: root.allowManualLogin && root.currentIndex === root.manualIndex

  signal picked(int index)

  radius: Theme.radiusPanel
  implicitWidth: Theme.userPanelWidth
  implicitHeight: column.implicitHeight + Theme.px(28)

  Column {
    id: column
    anchors.fill: parent
    anchors.margins: Theme.px(12)
    anchors.topMargin: Theme.px(14)
    anchors.bottomMargin: Theme.px(14)
    spacing: Theme.px(3)

    Text {
      leftPadding: Theme.px(8)
      topPadding: Theme.px(3)
      bottomPadding: Theme.px(7)
      text: qsTr("users")
      color: Theme.ink(0.3)
      font.family: Theme.fontMono
      font.pixelSize: Theme.fs(9)
      font.letterSpacing: 0.08 * Theme.fs(9)
    }

    Repeater {
      model: root.users
      delegate: Rectangle {
        id: row
        required property int index
        required property string name
        required property string realName
        required property string icon
        readonly property bool selected: root.currentIndex === row.index

        width: column.width
        height: rowContent.implicitHeight + Theme.px(16)
        radius: Theme.radiusRow
        color: row.selected ? Theme.accentFill : hover.hovered ? Theme.hoverRow : "transparent"
        border.width: row.selected ? 1 : 0
        border.color: Theme.accentBorder

        Behavior on color { ColorAnimation { duration: 120 } }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.picked(row.index) }

        Row {
          id: rowContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Theme.px(9)
          anchors.rightMargin: Theme.px(9)
          spacing: Theme.px(11)

          Avatar {
            anchors.verticalCenter: parent.verticalCenter
            compact: true
            size: Theme.px(30)
            name: row.name
            realName: row.realName
            picture: row.icon
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: rowContent.width - Theme.px(30) - Theme.px(11)
            spacing: Theme.px(1)

            Text {
              width: parent.width
              text: row.name
              elide: Text.ElideRight
              color: row.selected ? Theme.text : Theme.ink(0.75)
              font.family: Theme.fontMono
              font.pixelSize: Theme.fs(11.5)
              font.weight: 500
            }
            Text {
              width: parent.width
              text: row.realName !== "" && row.realName !== row.name
                    ? row.realName : qsTr("local account")
              elide: Text.ElideRight
              color: Theme.ink(row.selected ? 0.35 : 0.3)
              font.family: Theme.fontMono
              font.pixelSize: Theme.fs(9)
            }
          }
        }
      }
    }

    // "other..." -- the mockup's third row, only when theme.conf allows it.
    Rectangle {
      id: manual
      visible: root.allowManualLogin
      width: column.width
      height: manualContent.implicitHeight + Theme.px(16)
      radius: Theme.radiusRow
      color: root.manualSelected ? Theme.accentFill : manualHover.hovered ? Theme.hoverRow : "transparent"
      border.width: root.manualSelected ? 1 : 0
      border.color: Theme.accentBorder

      HoverHandler { id: manualHover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: root.picked(root.manualIndex) }

      Row {
        id: manualContent
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.px(9)
        spacing: Theme.px(11)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.px(30); height: Theme.px(30)
          radius: width / 2
          color: Theme.white(0.07)
          border.width: 1
          border.color: Theme.hairline

          Text {
            anchors.centerIn: parent
            text: ">_"
            color: Theme.ink(0.6)
            font.family: Theme.fontMono
            font.pixelSize: Theme.fs(10)
            font.weight: 600
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.px(1)
          Text {
            text: qsTr("other…")
            color: root.manualSelected ? Theme.text : Theme.ink(0.75)
            font.family: Theme.fontMono
            font.pixelSize: Theme.fs(11.5)
            font.weight: 500
          }
          Text {
            text: qsTr("type a username")
            color: Theme.ink(0.3)
            font.family: Theme.fontMono
            font.pixelSize: Theme.fs(9)
          }
        }
      }
    }
  }
}
