import QtQuick
import QtQuick.Shapes

// One icon from Icons.js, drawn at `size` px. The paths are authored in a 16x16
// box and scaled here, so the stroke thins and thickens with the icon exactly
// as it does in an SVG.
Item {
  id: root

  property var icon: ({})
  property int size: 14
  property color color: Theme.ink(0.6)
  property real strokeWidth: root.icon.width !== undefined ? root.icon.width : 1.3
  // Fill-only extras the caller draws on top (the battery's charge bar).
  default property alias content: overlay.data

  implicitWidth: root.size
  implicitHeight: root.size

  Shape {
    id: shape
    anchors.centerIn: parent
    width: 16
    height: 16
    // Shapes anti-alias badly at small sizes without it, and the icons are 9-14px.
    preferredRendererType: Shape.CurveRenderer
    transform: Scale {
      origin.x: 8; origin.y: 8
      xScale: root.size / 16; yScale: root.size / 16
    }

    // One ShapePath for the outlined paths and one for the filled ones, each
    // with the icon's paths concatenated: SVG path data holds any number of
    // subpaths, and a Repeater cannot help here -- ShapePath is not an Item.
    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: root.icon.stroke !== undefined ? root.icon.stroke.join(" ") : "" }
    }
    ShapePath {
      strokeColor: "transparent"
      fillColor: root.color
      PathSvg { path: root.icon.fill !== undefined ? root.icon.fill.join(" ") : "" }
    }
  }

  Item { id: overlay; anchors.fill: parent }
}
