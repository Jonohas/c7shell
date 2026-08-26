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
// The XF86MonBrightness keys come in over `qs -c c7shell ipc call brightness up|down`
// rather than running ddcutil themselves, which is what keeps that true.
//
// Nothing here knows the name or the model of any monitor. Panels are
// discovered at startup and on hotplug -- see probe() -- because the hardcoded
// pair that used to live here named a monitor the user no longer owns, and
// addressed ddcutil by a model string that never matched anything.
Singleton {
  id: root

  // Raised whenever a key step lands, with the percentage that resulted --
  // Services/OsdSources.qml turns it into the OSD pill. Deliberately not fired
  // by set(), because a slider already shows its own value.
  signal stepped(int percentage)

  // One row per discovered backend:
  //   label     human name, for notifications and the settings page
  //   kind      "ddc" (external, over i2c) | "logind" (internal backlight)
  //   dev       how the backend is addressed: an i2c bus number, or the
  //             /sys/class/backlight device name
  //   connector the DRM connector the panel hangs off ("DP-4", "eDP-1"), which
  //             is exactly what Hyprland calls the monitor, so a row can be
  //             found from focusedMonitor.name with no string matching at all
  //   value/max current level in the backend's own units (DDC counts to 100,
  //             the backlight to 65535); -1 = not read yet
  //   error     why the row has no value, once we have stopped trying
  //   tries     read attempts spent
  //
  // Keying on the connector rather than on the model is what survives the DP-N
  // renumbering a dock re-enumeration causes: the connector is re-read from
  // ddcutil on every hotplug, so it is never stale, and it is the only name
  // Hyprland and ddcutil agree on.
  //
  // A plain array rather than a ListModel: reassigning it emits a change
  // signal, so `value` can be bound to. ListModel.get() cannot.
  property var screens: []

  // False until the first probe has answered. Without it a key pressed during
  // startup reports "no backend for DP-4" when the truth is "not looked yet".
  property bool probed: false

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

  // -- discovery --------------------------------------------------------------

  // Partial results: the two probes answer independently and the row list is
  // only rebuilt once both have.
  property var foundBacklights: []
  property var foundPanels: []
  property int probesLeft: 0

  function probe() {
    if (root.probesLeft > 0) return   // one in flight already
    root.probesLeft = 2
    lsBacklight.running = true
    ddcDetect.running = true
  }

  // Hyprland names the built-in panel eDP-N and monitors.lua relies on that
  // being stable, so the backlight device is tied to whichever connector starts
  // eDP. A machine with no internal panel simply has no eDP monitor and the row
  // never matches anything, which is the correct quiet outcome.
  function internalConnector() {
    const m = Hyprland.monitors.values.find(v => v.name.startsWith("eDP"))
    return m ? m.name : ""
  }

  // "IVM:PL3466WQ:1174003000146" -> "PL3466WQ". Cosmetic only; nothing is
  // addressed by it.
  function modelLabel(monitor) {
    const parts = (monitor || "").split(":")
    return parts.length > 1 && parts[1] !== "" ? parts[1] : (monitor || "external")
  }

  // `ddcutil detect --brief` prints one block per display, each headed at
  // column 0 by "Display N" or "Invalid display" and indented underneath:
  //
  //   Display 1
  //      I2C bus:          /dev/i2c-16
  //      DRM connector:    card1-DP-4
  //      Monitor:          IVM:PL3466WQ:1174003000146
  //
  // The invalid blocks are the DDC-less i2c buses the GPU also exposes (both
  // eDP entries here) -- they are normal, not a fault. A valid block with no
  // DRM connector cannot be tied to a Hyprland monitor, so it is dropped rather
  // than guessed at.
  function parseDetect(text) {
    const out = []
    let cur = null
    for (const line of text.split("\n")) {
      if (line.trim() !== "" && !/^\s/.test(line)) {
        if (cur) out.push(cur)
        cur = /^Display\s/.test(line) ? { connector: "", bus: -1, model: "" } : null
        continue
      }
      if (!cur) continue
      let m = line.match(/DRM connector:\s*(?:card\d+-)?(\S+)/)
      if (m) cur.connector = m[1]
      m = line.match(/I2C bus:\s*\/dev\/i2c-(\d+)/)
      if (m) cur.bus = parseInt(m[1])
      m = line.match(/Monitor:\s*(\S+)/)
      if (m) cur.model = m[1]
    }
    if (cur) out.push(cur)
    return out.filter(d => d.connector !== "" && d.bus >= 0)
  }

  function compose() {
    if (--root.probesLeft > 0) return

    const rows = []
    // ponytail: the first backlight device only. Mapping several of them onto
    // connectors needs sysfs' drm links; no machine here has two, and one wrong
    // guess is worse than none.
    if (root.foundBacklights.length > 0) {
      rows.push({ label: "Laptop", kind: "logind", dev: root.foundBacklights[0],
                  connector: root.internalConnector(),
                  value: -1, max: 65535, error: "", tries: 0 })
    }
    for (const p of root.foundPanels) {
      rows.push({ label: root.modelLabel(p.model), kind: "ddc", dev: `${p.bus}`,
                  connector: p.connector,
                  value: -1, max: 100, error: "", tries: 0 })
    }

    // Carry levels already read across a re-probe, so a hotplug on another
    // connector does not blank the slider of a panel that never moved.
    for (const r of rows) {
      const old = root.screens.find(s => s.kind === r.kind && s.dev === r.dev)
      if (old) { r.value = old.value; r.max = old.max }
    }

    root.screens = rows
    root.probed = true
    for (let i = 0; i < rows.length; i++)
      if (rows[i].kind === "ddc") root.enqueueRead(i)
  }

  Process {
    id: lsBacklight
    command: ["ls", "-1", "/sys/class/backlight"]
    stdout: StdioCollector {
      onStreamFinished: root.foundBacklights = text.trim().split("\n").filter(l => l !== "")
    }
    // No backlight directory at all is a desktop, not a fault.
    stderr: StdioCollector {}
    onExited: root.compose()
  }

  Process {
    id: ddcDetect
    command: ["ddcutil", "detect", "--brief"]
    stdout: StdioCollector { onStreamFinished: root.foundPanels = root.parseDetect(text) }
    // ddcutil exits non-zero merely for having found an invalid display, and
    // finding nothing at all is the normal state on the road. Either way the
    // parse above is the answer; there is nothing here worth a warning.
    stderr: StdioCollector {}
    onExited: root.compose()
  }

  Component.onCompleted: root.probe()

  // A dock re-enumeration fires several screen changes in a row and ddcutil
  // takes ~1s, so coalesce them.
  Connections {
    target: Quickshell
    function onScreensChanged() { rediscover.restart() }
  }

  Timer {
    id: rediscover
    interval: 1500
    onTriggered: root.probe()
  }

  // -- lookups ----------------------------------------------------------------

  function rowFor(connector) {
    return root.screens.findIndex(s => s.connector === connector)
  }

  function percent(i) {
    const s = root.screens[i]
    // A chip can evaluate this while the singleton is still being rebuilt on a
    // reload, so a missing row is a real state, not a bug.
    if (!s) return 0
    return s.max > 0 ? Math.round(s.value / s.max * 100) : 0
  }

  // For the settings page: does this connector have a backend, and at what level.
  function hasBackend(connector) { return root.rowFor(connector) >= 0 }
  function percentFor(connector) { return root.percent(root.rowFor(connector)) }
  function setPercent(connector, pc) {
    const i = root.rowFor(connector)
    if (i < 0) return
    root.set(i, pc / 100 * root.screens[i].max)
  }

  // The panel the keys act on: whichever monitor has focus.
  readonly property int focusedRow: root.rowFor(Hyprland.focusedMonitor?.name ?? "")
  readonly property int percentage: root.percent(root.focusedRow)

  // -- the i2c queue ----------------------------------------------------------
  // One process, one job at a time, reads and writes in the same line. ddcutil's
  // own flock gives up after 3s under contention and the value lands garbage --
  // an overlapping pair once put this panel at 0 instead of 100 -- and a read
  // racing a write is the same hazard. Serialising both here is what makes this
  // singleton the only thing touching the bus.
  //
  // A round trip is ~0.1-0.7s, so writes move the slider optimistically and only
  // the last value per row is sent, not every step of a drag.
  property var jobs: []
  property real jobStarted: 0

  // Past this a ddcutil is wedged, and without the kill it holds the queue and
  // spins the timer at 5Hz for the rest of the session.
  readonly property int jobTimeout: 8000

  function enqueueRead(i) {
    if (root.jobs.some(j => j.row === i && j.read)) return
    root.jobs.push({ row: i, read: true, value: 0 })
    flush.start()
  }

  function enqueueWrite(i, value) {
    const existing = root.jobs.find(j => j.row === i && !j.read)
    if (existing) existing.value = value
    else root.jobs.push({ row: i, read: false, value: value })
    flush.start()
  }

  Timer {
    id: flush
    interval: 200
    repeat: true

    onTriggered: {
      if (io.running) {
        if (Date.now() - root.jobStarted < root.jobTimeout) return
        console.warn("brightness: ddcutil timed out, terminating it")
        io.signal(15)   // onExited then reports it like any other failure
        return
      }
      if (root.jobs.length === 0) return flush.stop()

      // Writes first: a read is background housekeeping, a write is the user
      // holding a key down.
      let n = root.jobs.findIndex(j => !j.read)
      if (n < 0) n = 0
      const job = root.jobs.splice(n, 1)[0]
      const s = root.screens[job.row]
      if (!s) return   // the row went away under a re-probe

      io.job = job
      root.jobStarted = Date.now()
      if (job.read)
        io.exec(["ddcutil", "--bus", s.dev, "--brief", "getvcp", "10"])
      else if (s.kind === "ddc")
        io.exec(["ddcutil", "--bus", s.dev, "--noverify", "setvcp", "10", `${job.value}`])
      else
        io.exec(["busctl", "call", "org.freedesktop.login1",
                 "/org/freedesktop/login1/session/auto",
                 "org.freedesktop.login1.Session", "SetBrightness", "ssu",
                 "backlight", s.dev, `${job.value}`])
    }
  }

  Process {
    id: io

    property var job: null

    stdout: StdioCollector {
      // "VCP 10 C <current> <max>"
      onStreamFinished: {
        if (!io.job || !io.job.read) return
        const f = text.trim().split(/\s+/)
        if (f.length < 5) return
        const i = io.job.row
        if (!root.screens[i]) return
        root.update(i, { value: parseInt(f[3]), max: parseInt(f[4]), error: "", tries: 0 })
      }
    }
    stderr: StdioCollector { id: ioErr }

    onExited: (code, status) => {
      // `job` deliberately outlives the run: the stdout collector's
      // streamFinished is not ordered against exited, and clearing it here once
      // dropped the parse of a perfectly good read.
      const job = io.job
      if (code === 0 && status === 0) return
      const s = root.screens[job?.row]
      if (!s) return
      const why = ioErr.text.trim().split("\n").pop() || `ddcutil exited ${code}`

      if (job.read) {
        // "Display not found" is not a fault -- it is the panel being
        // unplugged between the probe and the read, which is normal on the
        // road, and warning about it would put a permanent line in every
        // clean-restart check. Still worth one retry, because a monitor merely
        // slow to wake at login answers exactly the same way. Anything else --
        // an i2c permission problem, a bus error -- IS a fault and says so.
        const absent = /display not found/i.test(why)
        if (!absent) console.warn(`brightness: could not read ${s.label}: ${why}`)
        // Not a notification: nothing has been asked for yet. The row records
        // why, and stepFocused() says it the moment a key is pressed.
        root.update(job.row, { tries: s.tries + 1,
                               error: absent ? "it is not attached" : why })
        if (s.tries === 0) reread.restart()
        return
      }

      root.fail(`${s.label} did not change`, why)
      // The shown value is now a guess about hardware that refused. Re-read the
      // truth rather than leave the UI lying about it.
      if (s.kind === "ddc") { root.update(job.row, { tries: 0 }); reread.restart() }
    }
  }

  Timer {
    id: reread
    interval: 3000
    onTriggered: {
      for (let i = 0; i < root.screens.length; i++) {
        const s = root.screens[i]
        if (s.kind === "ddc" && s.tries < 2) root.enqueueRead(i)
      }
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
    onLoaded: {
      const v = parseInt(text())
      if (!isNaN(v) && root.sysfsRow >= 0)
        root.update(root.sysfsRow, { value: v, error: "" })
    }
  }

  FileView {
    path: root.sysfsDir ? `${root.sysfsDir}/max_brightness` : ""
    onLoaded: {
      const max = parseInt(text())
      if (!isNaN(max) && root.sysfsRow >= 0) root.update(root.sysfsRow, { max: max })
    }
  }

  function set(i, value) {
    if (i < 0 || !root.screens[i] || root.screens[i].value < 0) return
    const clamped = Math.max(0, Math.min(root.screens[i].max, Math.round(value)))
    root.update(i, { value: clamped })
    root.enqueueWrite(i, clamped)
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
    const name = Hyprland.focusedMonitor?.name ?? "this monitor"
    if (!root.probed) {
      root.fail("brightness unavailable", "still looking for attached panels")
      return
    }
    const i = root.focusedRow
    if (i < 0) {
      root.fail("brightness unavailable", `no brightness backend for ${name}`)
      return
    }
    const s = root.screens[i]
    if (s.value < 0) {
      root.fail(`${s.label} brightness unavailable`,
        s.error || "the panel has not reported a level yet")
      // Still trying is worth one more attempt on the key press itself.
      if (s.kind === "ddc") { root.update(i, { tries: 0 }); reread.restart() }
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
