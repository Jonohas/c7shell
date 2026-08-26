import QtQuick
import Quickshell
import Quickshell.Io
import "Search.js" as Search

// Fuzzy file search under $HOME, backed by a debounced background scan.
Item {
  id: root

  readonly property string name: "files"
  property var results: []
  property string query: ""

  readonly property string home: Quickshell.env("HOME")

  // fd when it is installed (skips dotfiles and .gitignore'd trees, and is far
  // faster); find otherwise. Depth and hit count are capped both ways so a
  // sweep of a large $HOME cannot stall the launcher.
  //
  // The query arrives as a positional argument, so nothing the user typed is
  // ever spliced into the script text.
  readonly property string script:
    'if command -v fd >/dev/null 2>&1; then'
    + ' fd --type f --max-depth 6 --color never --glob -- "*$1*" "$2" 2>/dev/null | head -n 40;'
    + ' else find "$2" -maxdepth 6 -type f -not -path "*/.*" -iname "*$1*" 2>/dev/null'
    + ' | head -n 40; fi'

  function search(text) {
    root.query = text.trim()
    // One or two characters under $HOME matches half the disk; not worth the
    // scan or the flicker.
    if (root.query.length < 2) { debounce.stop(); root.results = []; return }
    debounce.restart()
  }

  function take(text) {
    // The generation check. A scan that was signalled does not exit before the
    // next exec() reaches it, so its output can arrive after the query moved on;
    // ranking those stale paths against the new query is worse than showing
    // nothing. The query the scan was launched for is what identifies it.
    if (scan.forQuery !== root.query) return
    const paths = text.split("\n").filter(line => line !== "")
    root.results = Search.rank(root.query, paths, p => p, 30).map(path => {
      const cut = path.lastIndexOf("/")
      const dir = cut < 0 ? "" : path.slice(0, cut)
      return {
        path: path,
        dir: dir,
        title: cut < 0 ? path : path.slice(cut + 1),
        sub: `file · ${dir.startsWith(root.home) ? "~" + dir.slice(root.home.length) : dir}`,
        meta: "open",
        mono: Search.initials(cut < 0 ? path : path.slice(cut + 1))
      }
    })
  }

  function activate(row, mode) {
    if (mode === "terminal") {
      Quickshell.execDetached([Quickshell.env("TERMINAL") || "kitty", "-e",
        "sh", "-c", 'cd "$1" && exec "${SHELL:-/bin/sh}"', "sh", row.dir])
    } else {
      Quickshell.execDetached(["xdg-open", row.path])
    }
  }

  // A scan still running is for an older query; its output is useless now. But
  // exec() on a live Process is not a replacement -- it is either refused, which
  // leaves the previous query's results on screen for good, or it lands the
  // dying process's output under the new query. So the old one is signalled and
  // the new one waits for its exit, and take() checks which query it answers.
  function run() {
    // The query can have shrunk back below the floor while a scan was closing.
    if (root.query.length < 2) { scan.queued = false; return }
    if (scan.running) {
      scan.queued = true
      scan.signal(15)
      return
    }
    scan.queued = false
    scan.forQuery = root.query
    scan.exec(["sh", "-c", root.script, "sh", root.query, root.home])
  }

  Timer {
    id: debounce
    interval: 180
    onTriggered: root.run()
  }

  Process {
    id: scan
    property string forQuery: ""
    property bool queued: false
    stdout: StdioCollector { onStreamFinished: root.take(text) }
    onExited: if (scan.queued) root.run()
  }
}
