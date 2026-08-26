import QtQuick
import QtQuick.Shapes
import qs.Theme

// The wifi glyph from 1e: two arcs and a dot, each dimmed on its own once the
// signal drops below the level it stands for. Geometry is the mock's 16px
// viewBox — both arcs share the centre (8, 13.21) and the span -131.8°..-48.2°,
// they differ only in radius.
Item {
  id: root

  property int size: 14
  property real strength: 1        // 0..1, as NetworkManager reports it
  property color tint: Theme.alpha(Theme.text, 0.7)

  readonly property real unit: root.size / 16
  readonly property color dimTint: Theme.alpha(root.tint, 0.35)

  implicitWidth: root.size
  implicitHeight: root.size

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.strength >= 0.66 ? root.tint : root.dimTint
      strokeWidth: 1.4 * root.unit
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: 8 * root.unit
        centerY: 13.21 * root.unit
        radiusX: 9 * root.unit
        radiusY: 9 * root.unit
        startAngle: -131.8
        sweepAngle: 83.6
      }
    }

    ShapePath {
      strokeColor: root.strength >= 0.33 ? root.tint : root.dimTint
      strokeWidth: 1.4 * root.unit
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: 8 * root.unit
        centerY: 13.21 * root.unit
        radiusX: 5.4 * root.unit
        radiusY: 5.4 * root.unit
        startAngle: -131.8
        sweepAngle: 83.6
      }
    }
  }

  Rectangle {
    x: 6.7 * root.unit
    y: 10.5 * root.unit
    width: 2.6 * root.unit
    height: width
    radius: width / 2
    color: root.strength > 0 ? root.tint : root.dimTint
  }
}
