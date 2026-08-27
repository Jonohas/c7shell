import QtQuick

// The 226px panel to the right of the card: everything in
// /usr/share/wayland-sessions and /usr/share/xsessions, which is where the
// c7shell entry itself lives. Opened from the session pill in the bottom bar,
// and F1 cycles through it without opening anything.
GlassPanel {
  id: root

  property var sessions: null        // sddm's sessionModel
  property int currentIndex: 0

  signal picked(int index)

  radius: Theme.radiusPanel
  implicitWidth: Theme.sessionPanelWidth
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
      text: qsTr("session")
      color: Theme.ink(0.3)
      font.family: Theme.fontMono
      font.pixelSize: Theme.fs(9)
      font.letterSpacing: 0.08 * Theme.fs(9)
    }

    Repeater {
      model: root.sessions
      delegate: Rectangle {
        id: row
        required property int index
        required property string name
        required property string comment
        readonly property bool selected: root.currentIndex === row.index

        width: column.width
        height: rowContent.implicitHeight + Theme.px(18)
        radius: Theme.radiusSessionRow
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
          anchors.leftMargin: Theme.px(10)
          anchors.rightMargin: Theme.px(10)
          spacing: Theme.px(10)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.px(6); height: Theme.px(6)
            radius: width / 2
            color: row.selected ? Theme.accent : Theme.white(0.2)
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: rowContent.width - Theme.px(6) - Theme.px(10)
            spacing: Theme.px(1)

            Text {
              width: parent.width
              text: row.name
              elide: Text.ElideRight
              color: row.selected ? Theme.text : Theme.ink(0.75)
              font.family: Theme.fontMono
              font.pixelSize: Theme.fs(11)
              font.weight: 500
            }
            Text {
              width: parent.width
              // The .desktop Comment, which for c7shell.desktop is
              // "Hyprland with the c7shell Quickshell shell".
              text: row.comment
              elide: Text.ElideRight
              color: Theme.ink(row.selected ? 0.32 : 0.28)
              font.family: Theme.fontMono
              font.pixelSize: Theme.fs(9)
              visible: row.comment !== ""
            }
          }
        }
      }
    }

    Item { width: 1; height: Theme.px(6) }

    Rectangle {
      width: column.width
      height: 1
      color: Theme.white(0.07)
    }

    Text {
      leftPadding: Theme.px(10)
      topPadding: Theme.px(8)
      text: qsTr("the last session you used is preselected")
      width: column.width
      wrapMode: Text.WordWrap
      color: Theme.ink(0.28)
      font.family: Theme.fontMono
      font.pixelSize: Theme.fs(9)
    }
  }
}
