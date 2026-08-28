import QtQuick
import qs.Theme

// `mesa  25.1.2 → 25.1.4`, with the one number that moved picked out.
//
// The rule the mockups follow is stricter than "diff the strings": the *whole*
// changed number is highlighted, never the differing digit, and never the tail
// after it. 8.15.0 → 8.**16**.0, not 8.1**6**.0 and not 8.**16.0**. The old
// version is never highlighted at all -- it is context, and lighting up both
// sides doubles the noise for no extra information.
Row {
  id: root

  required property string oldVersion
  required property string newVersion
  property real fontSize: 10

  // Version segments as pacman writes them: epoch:upstream.parts-pkgrel. Split
  // on every separator and keep them, so the pieces can be rejoined verbatim.
  function segments(v) { return v.split(/([.:\-_+])/) }

  // Index of the first segment that differs, or -1 when they are identical.
  readonly property var delta: {
    const a = root.segments(root.oldVersion)
    const b = root.segments(root.newVersion)
    for (let i = 0; i < b.length; i++) {
      if (i >= a.length || a[i] !== b[i]) return { at: i, old: a[i] ?? "", now: b[i] }
    }
    return { at: -1, old: "", now: "" }
  }

  // Everything before the change, joined back up. Stays dim.
  readonly property string prefix:
    root.delta.at < 0 ? root.newVersion
                      : root.segments(root.newVersion).slice(0, root.delta.at).join("")

  // A purely numeric segment is highlighted whole (15 → **16**). One that
  // carries a marker keeps the marker dim, because the marker did not change:
  // r812 → r**819**.
  readonly property string lead: {
    if (root.delta.at < 0) return ""
    const now = root.delta.now, was = root.delta.old
    if (/^\d+$/.test(now)) return ""
    let i = 0
    while (i < now.length && i < was.length && now[i] === was[i] && !/\d/.test(now[i])) i++
    return now.slice(0, i)
  }

  readonly property string changed:
    root.delta.at < 0 ? "" : root.delta.now.slice(root.lead.length)

  readonly property string suffix:
    root.delta.at < 0 ? "" : root.segments(root.newVersion).slice(root.delta.at + 1).join("")

  spacing: 0

  component Dim: Text {
    font { family: Theme.fontMono; pixelSize: root.fontSize; weight: 400 }
    color: Theme.alpha(Theme.text, 0.38)
  }

  Dim { text: root.oldVersion !== "" ? `${root.oldVersion} → ` : "" }
  Dim { text: root.prefix }
  Dim { text: root.lead }
  Text {
    text: root.changed
    font { family: Theme.fontMono; pixelSize: root.fontSize; weight: 600 }
    color: Theme.accentSoft
  }
  Dim { text: root.suffix }
}
