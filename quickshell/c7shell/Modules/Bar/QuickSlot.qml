import QtQuick
import qs.Theme

// Handoff2 quick-settings rules: every icon is its own 24x22 r8 hit target
// with a 120ms hover pill; an open popover holds a crimson-tint pill. Width
// grows with content so the battery/updates slots fit their text.
Item {
  id: root

  property bool active: false
  property color hoverColor: Theme.hoverPill
  // Persistent tint behind conditional slots (screenshare, no-connectivity).
  property color slotColor: "transparent"
  // Its outline, for the states that are an alarm rather than a highlight --
  // the battery below its warn threshold draws the whole slot crimson.
  property color slotBorder: "transparent"
  default property alias content: inner.data
  // Slots whose content carries its own hover behaviour (the battery tooltip)
  // cannot detect it themselves: this MouseArea is above them.
  readonly property alias hovered: mouse.containsMouse
  signal clicked()

  implicitWidth: Math.max(24, inner.implicitWidth + 12)   // 6px side padding
  implicitHeight: 22

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusSlot
    color: root.active ? Theme.accentFillActive
      : mouse.containsMouse ? root.hoverColor
      : root.slotColor
    border.width: root.slotBorder.a > 0 ? 1 : 0
    border.color: root.slotBorder
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Row {
    id: inner
    anchors.centerIn: parent
    spacing: 5
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.clicked()
  }
}
