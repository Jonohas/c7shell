import QtQuick

// One item of the bottom bar: 30px tall, radius 10, hover pill at 8% white.
// Content is handed in, so the same button carries a label, an icon or both.
Rectangle {
  id: root

  property bool active: false        // the panel this opens is up
  property bool interactive: true
  default property alias content: row.data
  property alias spacing: row.spacing
  property int padding: Theme.px(12)

  signal clicked

  implicitWidth: row.implicitWidth + root.padding * 2
  implicitHeight: Theme.barItemHeight
  radius: Theme.radiusButton
  color: root.active ? Theme.hover
       : (hover.hovered && root.interactive) ? Theme.hover
       : "transparent"

  Behavior on color { ColorAnimation { duration: 120 } }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Theme.px(7)
  }

  HoverHandler {
    id: hover
    enabled: root.interactive
    cursorShape: Qt.PointingHandCursor
  }

  TapHandler {
    enabled: root.interactive
    onTapped: root.clicked()
  }
}
