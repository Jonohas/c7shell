pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
// For Terminal: the three things in this flow that belong in a terminal --
// "merge…", "view diff" and "view log" -- route through it.
import qs.Services

// The merged update flow, service side. Everything the bar, the dropdown, the
// wizard and the toast bind to lives here; none of them touch a process.
//
// The shape of this file follows the one decision the design makes: a dry run
// happens in the background *before* the dropdown is ever opened, so by the
// time it opens it already knows whether one click is enough. `verdict` is
// that answer and `clean` is the branch.
//
// arch-update is still underneath: its config, its state directory, its idea
// of which AUR helper to use and what counts as a post-update task. What it
// cannot provide is a parseable interface -- every stage of it is a `read -rp`
// against a TTY -- so bin/c7up is the machine-readable half and this talks to
// that. See bin/c7up's header for the division.
Singleton {
  id: root

  // -- the standing verdict --------------------------------------------------
  // Null until the first dry run lands, so the dropdown can show "checking"
  // rather than a count it cannot yet act on.
  property var verdict: null

  readonly property var sources: root.verdict?.sources ?? []
  readonly property var decisions: root.verdict?.decisions ?? []
  readonly property int total: root.sources.reduce((n, s) => n + s.items.length, 0)
  readonly property real size: root.verdict?.size ?? 0
  readonly property bool clean: root.verdict?.clean ?? true
  readonly property bool rebootPredicted: root.verdict?.reboot ?? false
  readonly property double checkedAt: root.verdict?.checked ?? 0
  property bool checking: false
  property string checkError: ""

  // The bar's crimson tint: a kernel or driver in the set is the one thing
  // worth colouring a 14px icon over.
  readonly property bool kernelPending:
    root.decisions.some(d => d.kind === "kernel" || d.kind === "driver")

  // -- the run ---------------------------------------------------------------
  property bool running: false
  property bool awaitingAuth: false
  property int doneCount: 0
  property int runTotal: 0
  // Per-source state, keyed as c7up emits it: running / done / failed.
  property var phases: ({})
  // The collapsed log. Capped: a full -Syu is thousands of lines and the view
  // only ever shows the last handful.
  property var lines: []
  property string logPath: ""

  // -- what the run left behind ----------------------------------------------
  property var result: null              // the last {"ev":"done"} payload
  property var pacnews: []               // configs still to review
  property var services: []              // units wanting a restart
  property bool rebootRequired: false

  // A clean run that turned out to need a decision anyway. The toast escalates
  // on this rather than the run having stopped mid-way to ask.
  readonly property bool needsReview: root.pacnews.length > 0 || root.rebootRequired

  signal finished(bool ok)
  // The wizard's only entry point. `entry` is which of the three reduced forms
  // it opens as: "approve" (step 1, the escalated path), "review" (step 3
  // alone, what the toast's "review now" opens) or "failure".
  signal wizardRequested(string entry)

  function openWizard(entry) { root.wizardRequested(entry) }

  // What the user unticked in step 1, as c7up decision ids.
  property var skipped: []

  function toggleSkip(id) {
    root.skipped = root.skipped.includes(id)
      ? root.skipped.filter(s => s !== id)
      : root.skipped.concat([id])
  }

  // Human "412 MB" for the button. Decimal units, because that is what pacman
  // and every mirror quote.
  function humanSize(bytes) {
    if (!bytes) return ""
    const u = ["B", "KB", "MB", "GB"]
    let i = 0, n = bytes
    while (n >= 1000 && i < u.length - 1) { n /= 1000; i++ }
    return `${n < 10 && i > 0 ? n.toFixed(1) : Math.round(n)} ${u[i]}`
  }

  function agoText() {
    if (!root.checkedAt) return "never checked"
    const s = Math.max(0, Math.floor(Date.now() / 1000 - root.checkedAt))
    if (s < 60) return "checked just now"
    if (s < 3600) return `checked ${Math.floor(s / 60)}m ago`
    if (s < 86400) return `checked ${Math.floor(s / 3600)}h ago`
    return `checked ${Math.floor(s / 86400)}d ago`
  }

  // Seconds as the design writes them: "3m 12s".
  function duration(secs) {
    if (secs === undefined || secs === null) return ""
    const m = Math.floor(secs / 60)
    return m > 0 ? `${m}m ${secs % 60}s` : `${secs}s`
  }

  // ---------------------------------------------------------------- refresh --
  function refresh() {
    if (root.checking || root.running) return
    root.checking = true
    root.checkError = ""
    verdictProc.running = true
  }

  function apply() {
    if (root.running) return
    root.running = true
    root.awaitingAuth = false
    root.doneCount = 0
    root.runTotal = root.total
    root.phases = ({})
    root.lines = []
    root.result = null
    const args = ["c7up", "run"]
    for (const id of root.skipped) args.push("--skip", id)
    runProc.command = args
    runProc.running = true
  }

  function abort() {
    if (!root.running) return
    // SIGINT, not SIGKILL: pacman traps it and rolls the transaction back,
    // which is the whole promise of the abort button. A kill would leave the
    // lock behind and the transaction half-prepared.
    runProc.signal(2)
  }

  function reloadPacnews() { pacnewProc.running = true }
  function resolvePacnew(action, path) { resolveProc.exec(["c7up", "resolve", action, path]) }

  // "merge…" is a three-pane editor, which is the one part of this flow that
  // genuinely belongs in a terminal. c7up execs $DIFFPROG there.
  function mergePacnew(path) { Terminal.run(["c7up", "resolve", "merge", path]) }

  // The failure state's "open in terminal": arch-update's own interactive run,
  // which is exactly the escape hatch a GUI should always leave open.
  function openInTerminal() { Terminal.run(["arch-update"]) }

  // Step 1's "view diff" on an AUR package whose PKGBUILD moved. A PKGBUILD is
  // a shell script and its diff is read in a pager, not a panel.
  function showDiff(pkg) { Terminal.run(["sh", "-c", `c7up aurdiff ${pkg} | less -R`]) }

  function openLog() {
    if (root.logPath !== "") Terminal.run(["less", "-R", root.logPath])
  }
  function restartServices(units) { restartProc.exec(["c7up", "restart"].concat(units)) }
  function reboot() { rebootProc.exec(["c7up", "reboot"]) }

  // ------------------------------------------------------------- processes --
  Process {
    id: verdictProc
    command: ["c7up", "verdict"]
    stdout: SplitParser {
      onRead: line => {
        if (line.trim() === "") return
        try {
          const ev = JSON.parse(line)
          if (ev.ev !== "verdict") return
          if (ev.error) { root.checkError = ev.error; return }
          root.verdict = ev
          // A verdict is also the moment to notice work parked by an earlier
          // run: pacnews outlive the process that made them.
          root.reloadPacnews()
        } catch (e) {
          console.warn("updates: unparseable verdict line:", line)
        }
      }
    }
    stderr: StdioCollector { id: verdictErr }
    onExited: code => {
      root.checking = false
      if (code !== 0 && root.checkError === "")
        root.checkError = verdictErr.text.trim() || `c7up verdict exited ${code}`
    }
  }

  Process {
    id: runProc
    stdout: SplitParser {
      onRead: line => {
        if (line.trim() === "") return
        let ev
        try { ev = JSON.parse(line) } catch (e) { return }
        switch (ev.ev) {
        case "start":
          root.runTotal = ev.total
          root.logPath = ev.log ?? ""
          break
        case "auth":
          root.awaitingAuth = ev.state === "waiting"
          break
        case "phase": {
          // Reassigned rather than mutated: QML does not see a property change
          // when the object it already points at is edited in place.
          const p = Object.assign({}, root.phases)
          p[ev.source] = ev
          root.phases = p
          break
        }
        case "progress":
          root.doneCount = ev.done
          if (ev.total) root.runTotal = ev.total
          break
        case "line": {
          const l = root.lines.concat([ev.text])
          root.lines = l.length > 400 ? l.slice(l.length - 400) : l
          break
        }
        case "done":
          root.result = ev
          root.pacnews = ev.pacnew ?? []
          root.services = ev.services ?? []
          root.rebootRequired = ev.reboot ?? false
          break
        }
      }
    }
    stderr: StdioCollector { id: runErr }
    onExited: code => {
      root.running = false
      root.awaitingAuth = false
      if (root.result === null) {
        // Aborted, or c7up died before it could say anything. Either way the
        // transaction was rolled back; the view says that rather than guessing.
        root.result = {
          ok: false,
          aborted: code === 130 || code === 2,
          error: runErr.text.trim(),
          done: root.doneCount,
          total: root.runTotal
        }
      }
      root.finished(root.result.ok === true)
      // A failure is the one place the wizard opens itself: it proposes
      // actions rather than asking a question, and there is nowhere else to
      // put them. A clean run that produced configs to review does NOT open
      // anything -- it escalates the toast, and the toast offers the wizard.
      if (root.result.ok !== true && !root.result.aborted) root.openWizard("failure")
      // The counts the bar shows are stale until the next dry run.
      refreshAfterRun.restart()
    }
  }

  Timer {
    id: refreshAfterRun
    interval: 2000
    onTriggered: root.refresh()
  }

  Process {
    id: pacnewProc
    command: ["c7up", "pacnew"]
    stdout: SplitParser {
      onRead: line => {
        if (line.trim() === "") return
        try {
          const ev = JSON.parse(line)
          if (ev.ev === "pacnew") root.pacnews = ev.files ?? []
        } catch (e) {}
      }
    }
    stderr: StdioCollector {}
  }

  Process {
    id: resolveProc
    stderr: StdioCollector {}
    onExited: root.reloadPacnews()
  }
  Process {
    id: restartProc
    stderr: StdioCollector {}
    onExited: root.services = []
  }
  Process {
    id: rebootProc
    stderr: StdioCollector {}
  }

  // The dry run rides the same cadence as the plain check it replaces.
  // arch-update's own timer keeps running alongside and writes the same state
  // files; the two agree because c7up writes them in arch-update's format.
  Timer {
    interval: 30 * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }
  // The first one waits for the network rather than racing login.
  Timer {
    interval: 60 * 1000
    running: true
    onTriggered: root.refresh()
  }
}
