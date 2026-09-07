import QtQuick
import qs.Theme

// The rectangle the capture will be cut to: outline, corner handles, and the
// size badge above it. Moved out of CaptureOverlay when the pixelate tool
// arrived and pushed that file past the length it should be read at; it holds
// no state, exactly as CaptureToolbar holds none.
Item {
  id: selection

  required property var overlay

  x: selection.overlay.selX
  y: selection.overlay.selY
  width: selection.overlay.selW
  height: selection.overlay.selH
  visible: selection.overlay.hasSelection && selection.overlay.target !== "all"

  Rectangle {
    anchors.fill: parent
    radius: 4                       // drawn geometry, like the bar's glyphs
    color: Theme.alpha(Theme.accent, 0.04)
    border.width: 1.5
    border.color: Theme.accent
  }

  Repeater {   // 7px corner handles
    model: [[0, 0], [1, 0], [0, 1], [1, 1]]
    Rectangle {
      required property var modelData
      x: modelData[0] * selection.width - 3.5
      y: modelData[1] * selection.height - 3.5
      width: 7; height: 7; radius: 2
      color: Theme.text
      border.width: 1.5
      border.color: Theme.accent
    }
  }

  Rectangle {   // "1680 × 920"
    anchors { right: parent.right; bottom: parent.top; bottomMargin: 8 }
    width: dims.implicitWidth + 16
    height: dims.implicitHeight + 6
    radius: Theme.radiusPip
    color: Theme.alpha(Theme.glassBase, 0.85)
    border.width: 1
    border.color: Theme.hairlineStrong

    Text {
      id: dims
      anchors.centerIn: parent
      // Logical pixels, the unit grim -g takes. The written PNG is this
      // multiplied by the monitor scale.
      text: `${Math.round(selection.overlay.selW)} × ${Math.round(selection.overlay.selH)}`
      font { family: Theme.fontMono; pixelSize: 10; weight: 600 }
      color: Theme.text
    }
  }
}
