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

  // Desktop id of the shell's own settings app (Assets/applications).
  readonly property string ownId: "c7shell-settings"

  // c7shell's settings app leads anything that reads as typing "settings".
  // Prepended, not hoisted or score-boosted: the fuzzy score puts it 42nd for
  // "set", behind nm-connection-editor and KDE's two system-settings entries
  // and outside rank()'s own limit, so there is nothing left in `hits` to
  // hoist. (A bare "s" does not even match -- one character against a long
  // haystack scores below the length penalty -- hence the 2-char floor in
  // isPrefixIntent rather than a check for presence.)
  function ownFirst(query, hits) {
    if (!Search.isPrefixIntent(query, "settings")) return hits
    const own = root.entries.find(e => e.id === root.ownId)
    return own ? [own].concat(hits.filter(e => e.id !== root.ownId)) : hits
  }

  function search(query) {
    const hits = root.ownFirst(query, Search.rank(query, root.entries, e =>
      `${e.name} ${e.genericName ?? ""} ${e.comment ?? ""} ${(e.keywords ?? []).join(" ")}`, 30))

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
