import QtQuick
import qs.Theme

// 32px result-row tile holding a two-letter monogram or a single glyph.
//
// Kept separate from Common/MonogramTile: this one takes a pre-computed glyph
// (calc "=", window dice) and a selected state; Common derives monograms from labels.
Rectangle {
  id: tile

  property alias text: label.text
  property bool selected: false

  implicitWidth: 32
  implicitHeight: 32
  radius: Theme.radiusTile
  color: tile.selected ? Theme.alpha(Theme.accent, 0.2) : Theme.surface07

  Text {
    id: label
    anchors.centerIn: parent
    font { family: Theme.fontMono; pixelSize: 11; weight: 700 }
    color: tile.selected ? Theme.accentSoft : Theme.alpha(Theme.text, 0.7)
  }
}
