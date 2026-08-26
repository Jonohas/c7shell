import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import "Search.js" as Search

// User scripts from ~/.config/qs/scripts plus the shell's own system actions.
// Providers are the service layer for the launcher, so running processes here
// is fine -- the view files must not.
Item {
  id: root

  readonly property string name: "actions"
  property var results: []

  readonly property string scriptDir: `${Quickshell.env("HOME")}/.config/qs/scripts`
  // [{ title, sub, meta, mono, run: [argv] }] -- scripts fill in after the scan.
  property var scripts: []

  // Lock lives here as well as in the power dropdown (3a) because the mockup
  // puts it in the launcher; the rest of the power verbs stay in 3a only.
  readonly property var systemActions: [{
    title: "lock session",
    sub: "system · hyprlock",
    meta: "ctrl+l",
    mono: "⏻",
    run: ["hyprlock"]
  }]

  // Settings pages, one row per built page (SP6 phase 2 pages join here when
  // they exist). `page` keys must match SettingsWindow's case labels.
  readonly property var settingsActions: ["appearance", "wifi", "bluetooth", "audio"]
    .map(p => ({
      title: `${p} settings`,
      sub: "settings · gambleland",
      meta: "open",
      mono: "⚙",
      page: p
    }))

  function lock() { Quickshell.execDetached(root.systemActions[0].run) }

  function search(query) {
    const all = root.scripts.concat(root.systemActions, root.settingsActions)
    root.results = Search.rank(query, all, a => `${a.title} ${a.sub}`, 30)
  }

  function activate(row, mode) {
    // Settings rows carry a page instead of an argv: falling through would
    // exec undefined.
    if (row.page !== undefined) { SettingsService.open(row.page); return }
    if (mode === "terminal") {
      Quickshell.execDetached([Quickshell.env("TERMINAL") || "kitty", "-e"].concat(row.run))
    } else {
      Quickshell.execDetached(row.run)
    }
  }

  // NUL-separated, not newline: a filename may legally contain a newline, and
  // splitting on one turned such a script into two rows, both of them naming
  // paths that do not exist.
  function take(text) {
    root.scripts = text.split("\0").filter(line => line !== "").map(file => ({
      title: file,
      sub: `action · ~/.config/qs/scripts`,
      meta: "run",
      mono: Search.initials(file),
      run: [`${root.scriptDir}/${file}`]
    }))
  }

  // One scan at startup. The directory is optional, so a missing one just
  // yields no scripts rather than an error.
  Process {
    id: scan
    stdout: StdioCollector { onStreamFinished: root.take(text) }
  }

  Component.onCompleted: scan.exec(["sh", "-c",
    '[ -d "$1" ] || exit 0; find "$1" -maxdepth 1 -type f -perm -u+x -printf "%f\\0" | sort -z',
    "sh", root.scriptDir])
}
