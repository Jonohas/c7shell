import QtQuick
import qs.Theme

// Two-letter tile standing in for an app icon: 28px in the 1d notification
// rows, 24px in the 1g mixer, 32px in the launcher's result rows -- where the
// text is handed in ready-made (calc "=", the window dice) instead of derived,
// which is the only thing the launcher's own copy of this ever did.
Rectangle {
  id: root

  property string label: ""
  property int size: 28
  property bool accented: false
  // Pre-computed text, when the caller has one: shown instead of the monogram.
  property string glyph: ""

  // "Blue Yeti" → "by", "spotify" → "sp", "org.kde.foo" → "of".
  readonly property string monogram: {
    const words = root.label.trim().toLowerCase().split(/[\s._\-]+/).filter(w => w.length > 0)
    if (words.length === 0) return "?"
    if (words.length === 1) return words[0].slice(0, 2)
    return words[0].charAt(0) + words[1].charAt(0)
  }

  implicitWidth: root.size
  implicitHeight: root.size
  radius: Math.round(root.size / 3)
  color: root.accented ? Theme.alpha(Theme.accent, 0.16) : Theme.surface07

  Text {
    anchors.centerIn: parent
    text: root.glyph !== "" ? root.glyph : root.monogram
    font {
      family: Theme.fontMono
      pixelSize: root.size >= 32 ? 11 : root.size >= 28 ? 10 : 9
      weight: 700
    }
    color: root.accented ? Theme.accentSoft : Theme.alpha(Theme.text, 0.7)
  }
}
