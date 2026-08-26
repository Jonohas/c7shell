import QtQuick
import QtQuick.Shapes
import qs.Theme

// The 8px open ring that marks a scan in progress (1f). A Rectangle border
// cannot leave one side transparent, so the gap comes from an arc.
Shape {
  id: root

  property int size: 8
  property color arcColor: Theme.alpha(Theme.accentSoft, 0.6)

  implicitWidth: root.size
  implicitHeight: root.size
  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    strokeColor: root.arcColor
    strokeWidth: 1.5
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap

    PathAngleArc {
      centerX: root.size / 2
      centerY: root.size / 2
      radiusX: (root.size - 1.5) / 2
      radiusY: (root.size - 1.5) / 2
      startAngle: -90
      sweepAngle: 270
    }
  }

  RotationAnimator on rotation {
    from: 0
    to: 360
    duration: 900
    loops: Animation.Infinite
    running: root.visible
  }
}
