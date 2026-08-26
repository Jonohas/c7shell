pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.Services

// Brightness for every attached panel, and the only writer on the i2c bus.
//
// A singleton because views are instantiated per screen: as a plain widget
// property this ran one reader and one writer per monitor, and two ddcutil
// processes on one bus corrupt each other's writes.
//
// The XF86MonBrightness keys come in over `qs ipc call brightness up|down`
// rather than running ddcutil themselves, which is what keeps that true.
Singleton {
  id: root

  // Raised whenever a key step lands, with the percentage that resulted --
  // Services/OsdSources.qml turns it into the OSD pill. Deliberately not fired
  // by set(), because a slider already shows its own value.
  signal stepped(int percentage)

  // Each panel needs a different backend, and neither is a file you can just
  // write: the external monitor only answers DDC/CI over i2c, and the laptop's
  // /sys/class/backlight/amdgpu_bl1 is root-owned, so it goes through logind
  // instead (brightnessctl does the same thing but is not installed).
  //
  // `dev` addresses the backend. `match` addresses the panel, by connector name
  // or by a substring of its model string, so one value covers both a
  // ShellScreen (name/model) and a HyprlandMonitor (name/description) -- and
  // the model half survives the DP-N renumbering a dock re-enumeration causes.
  //
  // A plain array rather than a ListModel: reassigning it emits a change signal,
  // so `value` can be bound to. ListModel.get() cannot.
  // `error` is why the row has no value, once we have stopped trying -- empty
  // while a read is still outstanding. stepFocused() reads it out loud.
  property var screens: [
    { label: "Ultrawide", kind: "ddc",    dev: "LG ULTRAWIDE", match: "LG ULTRAWIDE", value: -1, max: 100, error: "" },
    { label: "Laptop",    kind: "logind", dev: "amdgpu_bl1",   match: "eDP-1",        value: -1, max: 65535, error: "" },
  ]

  // §8: a failure is a notification, never a console line nobody reads.
  // Deduped, because the caller is a key the user is holding down: without this
  // a dead panel answers a key repeat with twenty identical toasts.
  property string lastFail: ""
  property real lastFailAt: 0

  function fail(what, why) {
    const key = `${what}\n${why}`
    if (key === root.lastFail && Date.now() - root.lastFailAt < 5000) return
    root.lastFail = key
    root.lastFailAt = Date.now()
    console.warn(`brightness: ${what}: ${why}`)
    NotifServer.send(what, why)
  }

  function update(i, changes) {
    const next = root.screens.slice()
    next[i] = Object.assign({}, next[i], changes)
    root.screens = next
  }

  // -1 means not read yet, or not attached: ddcutil just exits non-zero when
  // the monitor is gone, which is what keeps a chip hidden on the road.
  function rowFor(name, description) {
    return root.screens.findIndex(s =>
      s.match === name || (description && description.includes(s.match)))
  }

  function rowForScreen(screen) {
    return screen ? root.rowFor(screen.name, screen.model) : -1
  }

  function rowForDev(dev) {
    return root.screens.findIndex(s => s.dev === dev)
  }

  function percent(i) {
    const s = root.screens[i]
    // A chip can evaluate this while the singleton is still being rebuilt on a
    // reload, so a missing row is a real state, not a bug.
    if (!s) return 0
    return s.max > 0 ? Math.round(s.value / s.max * 100) : 0
  }

  function put(dev, value, max) {
    const i = root.rowForDev(dev)
    if (i < 0 || isNaN(value)) return
    const cap = max > 0 ? max : root.screens[i].max
    root.update(i, { max: cap, value: Math.max(0, Math.min(cap, value)) })
  }

  // The panel the keys act on: whichever monitor has focus.
  readonly property int focusedRow: root.rowFor(Hyprland.focusedMonitor?.name ?? "",
                                                Hyprland.focusedMonitor?.description ?? "")
  readonly property int percentage: root.percent(root.focusedRow)

  // The one read of the DDC panel, and the one thing standing between the
  // brightness keys and a dead session: until this lands, `value` is -1 and
  // set()/step() early-return. ddcutil exits non-zero for a monitor still
  // waking at login, a dock that has not enumerated yet, or missing i2c
  // permission -- all transient enough to be worth one retry, and none of them
  // worth failing in silence.
  Process {
    id: ddcRead
    running: true
    command: ["ddcutil", "--model", "LG ULTRAWIDE", "--brief", "getvcp", "10"]

    property int tries: 0

    stdout: StdioCollector {
      // "VCP 10 C <current> <max>"
      onStreamFinished: {
        const f = text.trim().split(/\s+/)
        if (f.length < 5) return
        root.put("LG ULTRAWIDE", parseInt(f[3]), parseInt(f[4]))
        const i = root.rowForDev("LG ULTRAWIDE")
        if (i >= 0) root.update(i, { error: "" })
        ddcRead.tries = 0
      }
    }
    stderr: StdioCollector { id: ddcReadErr }

    onExited: (code, status) => {
      if (code === 0 && status === 0) return
      const why = ddcReadErr.text.trim().split("\n").pop() || `ddcutil exited ${code}`
      // "Display not found" is not a fault -- it is the panel being unplugged,
      // which is the normal state on the road, and warning about it twice per
      // start would put a permanent two lines in every clean-restart check.
      // Still worth the one retry, because a monitor that is merely slow to
      // wake at login answers exactly the same way. Anything else -- an i2c
      // permission problem, a bus error -- IS a fault and says so out loud.
      const absent = /display not found/i.test(why)
      // Not a notification on the first failure either: nothing has been asked
      // for yet. The row records why, and stepFocused() says it the moment a
      // key is pressed.
      if (!absent) console.warn(`brightness: could not read the ultrawide: ${why}`)
      if (ddcRead.tries++ === 0) return reread.restart()
      const i = root.rowForDev("LG ULTRAWIDE")
      if (i >= 0) root.update(i, { error: absent ? "it is not attached" : why })
    }
  }

  Timer {
    id: reread
    interval: 3000
    // The write queue is the only writer on i2c and a concurrent read is the
    // same hazard that once blacked this panel out: wait it out, never race it.
    onTriggered: {
      if (write.running || Object.keys(root.pending).length > 0) return reread.restart()
      if (!ddcRead.running) ddcRead.running = true
    }
  }

  // The logind panel is a plain readable file, so it needs no process at all.
  // Watching it also corrects the optimistic value set() writes, and picks up
  // anything else that moves the backlight.
  readonly property int sysfsRow: root.screens.findIndex(s => s.kind === "logind")
  readonly property string sysfsDev: root.sysfsRow >= 0 ? root.screens[root.sysfsRow].dev : ""
  readonly property string sysfsDir: root.sysfsDev ? `/sys/class/backlight/${root.sysfsDev}` : ""

  FileView {
    path: root.sysfsDir ? `${root.sysfsDir}/brightness` : ""
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.put(root.sysfsDev, parseInt(text()), -1)
  }

  FileView {
    path: root.sysfsDir ? `${root.sysfsDir}/max_brightness` : ""
    onLoaded: {
      const max = parseInt(text())
      if (!isNaN(max) && root.sysfsRow >= 0) root.update(root.sysfsRow, { max: max })
    }
  }

  // An unguarded write was the second half of the silence: setvcp can fail on
  // exactly the same conditions the read can, and the optimistic value below
  // keeps the slider and the OSD claiming a level the panel never took.
  Process {
    id: write

    property int row: -1
    stderr: StdioCollector { id: writeErr }

    onExited: (code, status) => {
      if (code === 0 && status === 0) return
      const s = root.screens[write.row]
      const why = writeErr.text.trim().split("\n").pop() || `exited ${code}`
      root.fail(`${s?.label ?? "brightness"} did not change`, why)
      // The shown value is now a guess about hardware that refused. Re-read the
      // truth rather than leave the UI lying about it.
      if (s?.kind === "ddc") { ddcRead.tries = 0; reread.restart() }
    }
  }

  // Writes queue rather than overlap. ddcutil's flock gives up after 3s under
  // contention and the value lands garbage -- an overlapping pair put this
  // panel at 0 instead of 100. A round trip is ~0.7s too, so the slider moves
  // optimistically and only the last value per screen is sent, not every step
  // of a drag.
  property var pending: ({})
  property real writeStarted: 0

  // A round trip is ~0.7s and ddcutil's own flock gives up at 3s, so anything
  // past this is a wedged process -- and without the kill it holds the queue and
  // spins this timer at 5Hz for the rest of the session.
  readonly property int writeTimeout: 8000

  Timer {
    id: flush
    interval: 200
    repeat: true

    onTriggered: {
      if (write.running) {
        if (Date.now() - root.writeStarted < root.writeTimeout) return
        console.warn("brightness: write timed out, terminating it")
        write.signal(15)   // onExited then reports it like any other failure
        return
      }

      const rows = Object.keys(root.pending)
      if (rows.length === 0) return flush.stop()

      const i = parseInt(rows[0])
      const value = root.pending[i]
      delete root.pending[i]

      const s = root.screens[i]
      write.row = i
      root.writeStarted = Date.now()
      write.exec(s.kind === "ddc"
        ? ["ddcutil", "--model", s.dev, "--noverify", "setvcp", "10", `${value}`]
        : ["busctl", "call", "org.freedesktop.login1",
           "/org/freedesktop/login1/session/auto",
           "org.freedesktop.login1.Session", "SetBrightness", "ssu",
           "backlight", s.dev, `${value}`])
    }
  }

  function set(i, value) {
    if (i < 0 || root.screens[i].value < 0) return
    const clamped = Math.max(0, Math.min(root.screens[i].max, Math.round(value)))
    root.update(i, { value: clamped })
    root.pending[i] = clamped
    flush.start()
  }

  // 10% a step, so both backends land in the same places despite one counting
  // to 100 and the other to 65535.
  function step(i, dir) {
    if (i < 0 || root.screens[i].value < 0) return
    root.set(i, root.screens[i].value + dir * root.screens[i].max * 0.1)
    root.stepped(root.percent(i))
  }

  // The keys' entry point, and the only place that can tell the user why a key
  // press did nothing. step() early-returns on both of these, and returns
  // BEFORE stepped(), so without this the keys are dead and no OSD appears
  // either -- a silent failure the user cannot even see the shape of.
  function stepFocused(dir) {
    const i = root.focusedRow
    if (i < 0) {
      const name = Hyprland.focusedMonitor?.name ?? "this monitor"
      root.fail("brightness unavailable", `no brightness backend for ${name}`)
      return
    }
    const s = root.screens[i]
    if (s.value < 0) {
      root.fail(`${s.label} brightness unavailable`,
        s.error || "the panel has not reported a level yet")
      // Still trying is worth one more attempt on the key press itself.
      if (s.kind === "ddc") { ddcRead.tries = 0; reread.restart() }
      return
    }
    root.step(i, dir)
  }

  IpcHandler {
    target: "brightness"

    function up(): void { root.stepFocused(1) }
    function down(): void { root.stepFocused(-1) }
  }
}
