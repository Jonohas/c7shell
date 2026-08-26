import QtQuick
import qs.Theme

// The r10 list row the wi-fi, bluetooth and audio pages are built from: a
// leading visual, a title over an optional subtitle, and whatever the page
// wants right-aligned. `active` is the crimson-tinted state the mocks give the
// connected network / connected device / current output.
Rectangle {
  id: root

  property alias leading: leadingSlot.data
  default property alias trailing: trailingSlot.data

  property string title: ""
  property string subtitle: ""
  property bool active: false
  property bool hoverable: true
  // Width AND height reserved for the leading visual; 0 draws none. Explicit
  // rather than measured, so the title column never re-lays out as an icon
  // finishes loading.
  property int leadingSize: 0

  signal clicked()

  readonly property bool hovered: mouse.containsMouse

  implicitHeight: 44
  radius: Theme.radiusTile
  color: root.active ? Theme.accentFill
    : (root.hoverable && mouse.containsMouse ? Theme.surface04 : "transparent")
  border.width: root.active ? 1 : 0
  border.color: Theme.accentBorder

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    // Rows that only display still need the hover tint suppressed, not the
    // pointer swallowed by a disabled MouseArea.
    onClicked: if (root.hoverable) root.clicked()
  }

  Item {
    id: leadingSlot
    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
    width: root.leadingSize
    height: root.leadingSize
    visible: root.leadingSize > 0
  }

  Column {
    anchors {
      left: parent.left
      leftMargin: root.leadingSize > 0 ? 12 + root.leadingSize + 11 : 12
      right: trailingSlot.left
      rightMargin: 8
      verticalCenter: parent.verticalCenter
    }
    spacing: 2

    Text {
      width: parent.width
      text: root.title
      font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
      color: root.active ? Theme.text : Theme.alpha(Theme.text, 0.85)
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: root.subtitle !== ""
      text: root.subtitle
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.45)
      elide: Text.ElideRight
    }
  }

  // Trailing items are mixed heights — 20px chips next to 13px readouts — so
  // each one anchors its own verticalCenter. A Row permits vertical anchors on
  // its children (only left/right/horizontalCenter/fill/centerIn are refused),
  // and it has no verticalItemAlignment of its own; that belongs to Grid.
  Row {
    id: trailingSlot
    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
    spacing: 8
  }
}
