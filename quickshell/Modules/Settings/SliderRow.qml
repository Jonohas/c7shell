import QtQuick
import qs.Theme
import qs.Common

// 2b sliders card row: fixed label column, the shared crimson slider, right-aligned
// value. Works in real units — `value`, `from` and `to` are px, passes, a
// multiplier — and hands back a value already snapped to `step`, so the page
// never has to un-normalise a 0..1 position itself.
Item {
  id: root

  required property string label
  required property real value
  required property real from
  required property real to

  property real step: 1
  property int decimals: 0
  property string suffix: ""

  signal moved(real value)

  readonly property real span: root.to - root.from

  // Float steps land on 0.30000000000000004 without the round-trip.
  function quantize(v) {
    return parseFloat((Math.round(v / root.step) * root.step).toFixed(3))
  }

  implicitHeight: 13

  Text {
    id: name
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    // Wide enough for the longest label on the page ("inactive opacity", 16
    // mono glyphs); at 90 it and "animation speed" both elided.
    width: 108
    text: root.label
    font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
    color: Theme.alpha(Theme.text, 0.7)
    elide: Text.ElideRight
  }

  CrimsonSlider {
    anchors {
      left: name.right; leftMargin: 12
      right: readout.left; rightMargin: 12
      verticalCenter: parent.verticalCenter
    }
    value: root.span === 0 ? 0 : (root.value - root.from) / root.span
    onMoved: v => root.moved(root.quantize(root.from + v * root.span))
  }

  Text {
    id: readout
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    width: 36
    horizontalAlignment: Text.AlignRight
    text: root.value.toFixed(root.decimals) + root.suffix
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: Theme.alpha(Theme.text, 0.45)
  }
}
