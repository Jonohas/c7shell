import QtQuick
import QtQuick.Effects

// The shell's Common/GlassPanel, minus the blur: sddm draws straight onto the
// framebuffer with no compositor under it, so there is nothing to blur and the
// fill alone carries the glass. Shadow included here rather than left to the
// caller, because every panel in the greeter has one.
Rectangle {
  id: root

  property real shadowBlur: Theme.px(100)
  property real shadowOffset: Theme.px(34)
  property color shadowColor: Theme.shadow

  radius: Theme.radiusPanel
  color: Theme.panel
  border.width: 1
  border.color: Theme.hairline

  RectangularShadow {
    anchors.fill: root
    radius: root.radius
    color: root.shadowColor
    offset.y: root.shadowOffset
    blur: root.shadowBlur
    spread: 0
    z: -1
  }
}
