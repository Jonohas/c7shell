import QtQuick
import QtQuick.Effects

// One of the shell's lucide SVGs, painted at `size` px in `color`. Same
// approach as the shell's Common/Icon.qml: Qt SVG has no currentColor, so the
// white-stroked asset is drawn hidden and recoloured by a MultiEffect.
//
// That is a shader effect, so it needs the scenegraph's GPU backend -- the same
// one Hyprland and the shell already require of this machine, and what sddm
// gets on anything that can run the session behind it. Under the software
// backend it draws nothing; tests/test-greeter.sh says so out loud rather than
// rendering a greeter with holes in it.
//
// The greeter used to carry its own hand-authored copy of every path (a 47-line
// Icons.js drawn in a 16-unit box) because the assets under ~/.config are not
// readable by the sddm user. The packaged copy at Theme.iconsDir is -- and it
// has the real glyphs, which the redrawn ones were only close to.
Item {
  id: root

  property string name
  property int size: 14
  property color color: Theme.ink(0.6)

  implicitWidth: root.size
  implicitHeight: root.size

  Image {
    id: img
    anchors.fill: parent
    // Empty name = no fetch, so a caller binding the name late does not make
    // Image warn about ".svg" -- and test-greeter.sh fails on any warning.
    source: root.name !== "" ? `${Theme.iconsDir}/${root.name}.svg` : ""
    // Twice the drawn size: these render at 9-14px, where an SVG rasterised
    // 1:1 loses the thin strokes.
    sourceSize: Qt.size(root.size * 2, root.size * 2)
    visible: false
  }
  MultiEffect {
    anchors.fill: img
    source: img
    colorization: 1
    colorizationColor: root.color
  }
}
