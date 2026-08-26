import QtQuick
import Quickshell.Hyprland
import "Search.js" as Search

// Open toplevels. ↵ focuses the window through the Lua dispatch dialect --
// stock dispatcher strings do not work on this Hyprland (CONVENTIONS).
Item {
  id: root

  readonly property string name: "windows"
  property var results: []

  // ⚀..⚅ are U+2680..U+2685; anything outside that (special workspaces, >6)
  // falls back to a dot rather than printing a stray glyph.
  function dice(id) {
    return id >= 1 && id <= 6 ? String.fromCharCode(0x267f + id) : "·"
  }

  function search(query) {
    // Snapshot to plain JS first: the model must not hold toplevel pointers.
    const windows = Hyprland.toplevels.values.map(t => ({
      address: t.address,
      title: t.title || t.lastIpcObject?.class || "window",
      workspace: t.workspace ? t.workspace.id : 0
    }))

    root.results = Search.rank(query, windows, w => w.title, 30).map(w => ({
      address: w.address,
      title: w.title,
      sub: `window · workspace ${root.dice(w.workspace)} ${w.workspace}`,
      meta: "jump",
      mono: Search.initials(w.title)
    }))
  }

  function activate(row) {
    Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${row.address}" })`)
  }
}
