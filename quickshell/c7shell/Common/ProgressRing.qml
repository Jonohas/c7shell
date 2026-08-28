import QtQuick
import QtQuick.Shapes
import qs.Theme

// The thin ring the bar icon becomes while an update runs. Closing the
// dropdown over a running update is explicitly allowed, so the bar has to be
// able to say "still going" in 13px without a number.
Shape {
  id: root

  property real fraction: 0
  property color trackColor: Theme.surface10
  property color ringColor: Theme.accent

  implicitWidth: 13
  implicitHeight: 13
  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    strokeColor: root.trackColor
    strokeWidth: 1.6
    fillColor: "transparent"
    PathAngleArc {
      centerX: root.width / 2; centerY: root.height / 2
      radiusX: (root.width - 1.6) / 2; radiusY: (root.height - 1.6) / 2
      startAngle: -90; sweepAngle: 360
    }
  }

  ShapePath {
    strokeColor: root.ringColor
    strokeWidth: 1.6
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap

    PathAngleArc {
      centerX: root.width / 2; centerY: root.height / 2
      radiusX: (root.width - 1.6) / 2; radiusY: (root.height - 1.6) / 2
      startAngle: -90
      // Never a full 360 while it is still going: a closed ring reads as done.
      sweepAngle: Math.max(6, Math.min(354, root.fraction * 360))
      Behavior on sweepAngle { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }
  }
}
