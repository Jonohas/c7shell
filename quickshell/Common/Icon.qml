import QtQuick
import QtQuick.Effects
import qs.Theme

// White-painted SVG recolored at runtime (Qt SVG has no currentColor).
Item {
  property string name
  property color tint: Theme.text
  property real size: 14

  width: size; height: size

  Image {
    id: img
    anchors.fill: parent
    // Empty name = no fetch: delegates often bind name late, and Image would
    // otherwise warn about ".svg" on every instantiation.
    source: name !== "" ? `${Theme.iconsDir}/${name}.svg` : ""
    sourceSize: Qt.size(width * 2, height * 2)
    visible: false
  }
  MultiEffect {
    anchors.fill: img
    source: img
    colorization: 1
    colorizationColor: tint
  }
}
