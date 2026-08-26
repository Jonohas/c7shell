import QtQuick
import Quickshell
import qs.Services
import "Search.js" as Search

// Desktop entries, fuzzy-matched. ↵ launches, ctrl+↵ runs the Exec line in a
// terminal instead.
Item {
  id: root

  readonly property string name: "apps"
  property var results: []

  // Sorted once here so an empty query lists alphabetically -- rank() keeps
  // input order for equal scores.
  readonly property var entries: DesktopEntries.applications.values
    .filter(e => !e.noDisplay)
    .sort((a, b) => a.name.localeCompare(b.name))

  function search(query) {
    const hits = Search.rank(query, root.entries, e =>
      `${e.name} ${e.genericName ?? ""} ${e.comment ?? ""} ${(e.keywords ?? []).join(" ")}`, 30)

    // Rows carry the entry id, never the DesktopEntry pointer: a JS array of
    // live QObjects bound as a model has segfaulted here before (CONVENTIONS).
    root.results = hits.map(e => ({
      id: e.id,
      title: e.name,
      sub: `app · ${(e.genericName || e.comment || "application").toLowerCase()}`,
      meta: "open",
      mono: Search.initials(e.name),
      // Icon *name*, not a resolved path: ResultRow does the theme lookup, and
      // an entry with no Icon= line falls back to the monogram there.
      icon: e.icon ?? ""
    }))
  }

  function activate(row, mode) {
    const entry = DesktopEntries.byId(row.id)
    if (!entry) return

    if (mode !== "terminal") { entry.execute(); return }

    // Field codes (%f, %U, …) only mean something to a launcher passing files.
    const cmd = String(entry.execString).replace(/%[a-zA-Z]/g, "").trim()
    Terminal.run(["sh", "-c", cmd])
  }
}
