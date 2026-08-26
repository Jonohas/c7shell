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
  default property alias content: inner.data
  signal clicked()

  implicitWidth: Math.max(24, inner.implicitWidth + 12)   // 6px side padding
  implicitHeight: 22

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusSlot
    color: root.active ? Theme.accentFillActive
      : mouse.containsMouse ? root.hoverColor
      : root.slotColor
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
