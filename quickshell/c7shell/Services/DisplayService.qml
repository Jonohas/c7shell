pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Live monitor layout changes, for Modules/Settings/pages/DisplaysPage.qml.
// Views hold no Process of their own, so every hyprctl call lands here.
//
// `hyprctl keyword` does not work on this build: the config provider is lua and
// Hyprland answers keyword with "can't work with non-legacy parsers, use eval".
// So this speaks the same hl.monitor() dialect conf/monitors.lua does.
//
// Nothing here writes to conf/monitors.lua. That file carries a CATALOG and a
// set of PROFILES the user authored by hand, keyed on monitor description so
// they survive DP-N renumbering; a settings app rewriting it would clobber
// work no dialog can reconstruct. Persistence goes to a SEPARATE file,
// ~/.config/hypr/displays.json, which conf/displays.lua reads and lets
// override the profile -- same two-sided-JSON pattern as appearance.json.
Singleton {
  id: root

  Component.onCompleted: root.probeAll()

  // Last spec applied per output, so a slider drag coalesces into one hyprctl
  // instead of one per frame.
  property var queued: ({})

  // -- saved layouts --------------------------------------------------------
  // Keyed on the sorted descriptions of the monitors that are currently
  // ENABLED. Description, never connector name: the same panel has been DP-4
  // and DP-3 inside one session. conf/displays.lua computes the identical key
  // from Hyprland's own monitor list, minus anything its profile disables.
  readonly property string signature:
    Hyprland.monitors.values.map(m => m.description).sort().join("|")

  readonly property var layouts: adapter.layouts ?? ({})
  // Until the file has been read, `layouts` is still the adapter's empty
  // default: writing then would silently drop every OTHER desk's layout.
  property bool ready: false
  readonly property bool hasSaved: root.layouts[root.signature] !== undefined

  // Only concrete values are worth saving. "auto" and friends are a request to
  // let hyprland decide, which is what NOT having an entry already means, and
  // the lua side would refuse them anyway.
  function persistable(fields) {
    const out = {}
    if (/^-?\d+x-?\d+$/.test(fields.position ?? ""))
      out.position = fields.position
    if (/^\d+x\d+@[\d.]+$/.test(fields.mode ?? ""))
      out.mode = fields.mode
    if (typeof fields.scale === "number" && fields.scale >= 0.5 && fields.scale <= 3)
      out.scale = fields.scale
    if (Number.isInteger(fields.transform) && fields.transform >= 0 && fields.transform <= 3)
      out.transform = fields.transform
    return out
  }

  // JsonAdapter only notices whole-property assignment, so rebuild rather than
  // mutate in place.
  function persist(output, fields) {
    const mon = Hyprland.monitors.values.find(m => m.name === output)
    const keep = root.persistable(fields)
    // An empty signature means hyprland's monitor list has not been read yet;
    // saving under it would key a layout to no desk at all.
    if (!root.ready || !mon || root.signature === "" || Object.keys(keep).length === 0) return
    const layouts = Object.assign({}, root.layouts)
    const desk = Object.assign({}, layouts[root.signature])
    desk[mon.description] = Object.assign({}, desk[mon.description], keep)
    layouts[root.signature] = desk
    adapter.layouts = layouts
  }

  // Forget this desk, so the next reload comes back up on conf/monitors.lua's
  // own profile. A saved arrangement the user cannot clear would be worse than
  // no persistence at all.
  function forget() {
    if (!root.ready) return
    const layouts = Object.assign({}, root.layouts)
    delete layouts[root.signature]
    adapter.layouts = layouts
    // Forgetting is only half the answer -- the live layout is still whatever
    // was dragged. A reload re-runs conf/monitors.lua, which now finds nothing
    // saved and puts the profile back, so the button does what it says.
    reload.restart()
  }

  // -- profiles -------------------------------------------------------------
  // conf/monitors.lua writes this after every apply. Read-only on this side, and
  // the only way this app can see a profile that lives in lua: it does not parse
  // conf/monitors.lua, and it never will -- that file is hand-written.
  readonly property var profiles: stateAdapter.profiles ?? []
  readonly property string activeProfile: stateAdapter.active ?? ""
  readonly property bool activeForced: stateAdapter.forced ?? false

  // True for a profile the settings app owns. A lua profile can be selected and
  // shadowed, never renamed or deleted from here.
  function isSaved(name) {
    return (adapter.profiles ?? []).some(p => p.name === name)
  }

  FileView {
    id: stateFile

    path: `${Quickshell.env("HOME")}/.config/hypr/displays-state.json`
    watchChanges: true
    // Absent until hyprland's first apply with a version of conf/monitors.lua
    // that writes it. An empty picker is the honest answer, not a warning.
    printErrors: false

    onFileChanged: stateFile.reload()
    // Deliberately no onAdapterUpdated: writing this file back would fight the
    // compositor for ownership of it.

    JsonAdapter {
      id: stateAdapter

      property var profiles: []
      property string active: ""
      property bool forced: false
    }
  }

  // -- profile mutators -----------------------------------------------------
  // All four write displays.json and then reload: conf/monitors.lua is what
  // turns a profile into a layout, so the compositor has to re-read it. The
  // same reload timer `forget()` uses, for the same reason.

  //! Pin a profile, or pass "" to go back to auto-match.
  function selectProfile(name) {
    if (!root.ready) return
    adapter.active = name
    reload.restart()
  }

  //! Capture the live layout under `name`, replacing a saved profile of that
  //! name. Hyprland.monitors lists only the monitors that are ON, so membership
  //! records which displays this profile enables -- which is what a profile
  //! means on the lua side too.
  function saveProfile(name) {
    if (!root.ready || name === "") return
    const displays = {}
    for (const m of Hyprland.monitors.values) {
      displays[m.description] = root.persistable({
        position: `${m.x}x${m.y}`,
        mode: `${m.width}x${m.height}@${(m.lastIpcObject?.refreshRate ?? 0).toFixed(2)}`,
        scale: m.scale,
        transform: m.lastIpcObject?.transform ?? 0,
      })
    }
    // conf/displays.lua rejects a profile WHOLE if any one display lacks a
    // valid position, so a profile that is missing one anywhere would land in
    // the file and silently do nothing. Refuse to write it instead.
    if (Object.keys(displays).length === 0
        || Object.values(displays).some(d => !d.position)) return
    adapter.profiles = (adapter.profiles ?? [])
      .filter(p => p.name !== name)
      .concat([{ name: name, displays: displays }])
    adapter.active = name
    reload.restart()
  }

  //! Rename a saved profile. One write rather than a save plus a delete, so a
  //! reload cannot land between the two and find the profile under neither name.
  function renameProfile(from, to) {
    if (!root.ready || to === "" || from === to) return
    const list = adapter.profiles ?? []
    const src = list.find(p => p.name === from)
    if (!src) return
    adapter.profiles = list
      .filter(p => p.name !== from && p.name !== to)
      .concat([{ name: to, displays: src.displays }])
    if (adapter.active === from) adapter.active = to
    reload.restart()
  }

  //! Forget a saved profile. When it shadowed a hand-written one of the same
  //! name, this is the revert: conf/monitors.lua stops finding the JSON copy and
  //! the lua profile is a candidate again.
  function deleteProfile(name) {
    if (!root.ready) return
    adapter.profiles = (adapter.profiles ?? []).filter(p => p.name !== name)
    if (adapter.active === name) adapter.active = ""
    reload.restart()
  }

  Timer {
    id: reload
    // Long enough for FileView to have written the file the reload will read.
    interval: 250
    onTriggered: {
      if (hypr.running) return reload.restart()
      hypr.exec(["hyprctl", "reload"])
    }
  }

  FileView {
    id: file

    path: `${Quickshell.env("HOME")}/.config/hypr/displays.json`
    watchChanges: true
    // First run has no file; that is expected, not something to warn about.
    printErrors: false

    onFileChanged: file.reload()
    onAdapterUpdated: file.writeAdapter()
    onLoaded: root.ready = true
    // Same as AppearanceStore: create the file on first run so hyprland has
    // something valid to read, instead of both sides silently disagreeing.
    onLoadFailed: err => {
      if (err !== FileViewError.FileNotFound) return
      root.ready = true
      file.writeAdapter()
    }

    JsonAdapter {
      id: adapter

      // { "<desc>|<desc>": { "<desc>": { position, mode, scale } } }
      property var layouts: ({})
      // [ { name, displays: { "<desc>": { position, mode, scale } } } ]
      // Written here, read by conf/displays.lua. Order is match precedence.
      property var profiles: []
      // The profile the user pinned, "" for auto-match.
      property string active: ""
    }
  }

  function lua(v) {
    return typeof v === "string" ? `"${v}"` : `${v}`
  }

  // `fields` is an HL.MonitorSpec minus `output`: mode / position / scale /
  // transform, in hl.monitor()'s own names.
  function apply(output, fields) {
    // Connector names come from Hyprland and contain no quotes; refuse anything
    // else rather than build lua out of it.
    if (!/^[A-Za-z0-9-]+$/.test(output)) return
    root.persist(output, fields)
    root.queued[output] = fields
    debounce.restart()
  }

  Timer {
    id: debounce
    interval: 150
    onTriggered: {
      if (hypr.running) return debounce.restart()
      const outputs = Object.keys(root.queued)
      if (outputs.length === 0) return
      const calls = outputs.map(o => {
        const f = root.queued[o]
        const body = Object.keys(f).map(k => `${k}=${root.lua(f[k])}`).join(",")
        return `hl.monitor({output="${o}",${body}})`
      })
      root.queued = ({})
      hypr.exec(["hyprctl", "eval", calls.join(";")])
      // hl.monitor() does not push a monitor event for every field it changes,
      // so re-read rather than wait to be told.
      refresh.restart()
    }
  }

  Timer {
    id: refresh
    interval: 400
    onTriggered: { Hyprland.refreshMonitors(); root.probeAll() }
  }

  // -- enable / disable -----------------------------------------------------
  // A disabled monitor drops out of Hyprland.monitors entirely, so the settings
  // list -- which is built from that -- can no longer show it to re-enable. The
  // full output list, disabled ones included, only exists in `hyprctl monitors
  // all -j`; this reads it so the page can offer them back.
  //
  // Disabling is LIVE only: persistable() drops `disabled`, and PROFILES in
  // conf/monitors.lua keeps deciding which monitors are on across a reload. So
  // an accidental blackout survives no longer than the next reload, and there
  // is nothing here to un-say.
  property var allOutputs: []

  function probeAll() {
    if (!probe.running) probe.exec(["hyprctl", "monitors", "all", "-j"])
  }

  // on=false turns a screen off; on=true brings it back on its preferred mode.
  // Refuses to disable the last screen that would be left on -- counting the
  // ones already staged off -- so a commit can never black the desk out.
  function setEnabled(output, on) {
    if (!/^[A-Za-z0-9-]+$/.test(output)) return
    if (!on) {
      const offStaged = Hyprland.monitors.values
        .filter(m => root.stagedFor(m.name).disabled === true).length
      if (Hyprland.monitors.values.length - offStaged <= 1) return
    }
    root.stage(output, { disabled: !on })
  }

  // -- staged edits ---------------------------------------------------------
  // Every change on the displays page is held here, per output, until the user
  // presses apply -- so scale, mode, position and on/off all land in one go and
  // can be abandoned wholesale. The page reads stagedFor() to show the pending
  // value; commit() replays each through apply(), which is where the real
  // hyprctl and the persistence live.
  //   { "<output>": { scale?, mode?, position?, disabled? } }
  property var staged: ({})
  readonly property bool hasStaged: Object.keys(root.staged).length > 0

  function stagedFor(output) { return root.staged[output] ?? ({}) }

  // Rebuild rather than mutate: a var property only notifies on assignment.
  function stage(output, fields) {
    if (!/^[A-Za-z0-9-]+$/.test(output)) return
    const next = Object.assign({}, root.staged)
    next[output] = Object.assign({}, next[output], fields)
    root.staged = next
  }

  function commit() {
    for (const o of Object.keys(root.staged)) root.apply(o, root.staged[o])
    // Hold the staged values over the ~550ms it takes apply() to eval and
    // re-read, so the tiles and sliders do not rubber-band to the old live
    // value and back. Same 700ms the drag settle used to use.
    clearStaged.restart()
  }

  function revertStaged() { clearStaged.stop(); root.staged = ({}) }

  Timer { id: clearStaged; interval: 700; onTriggered: root.staged = ({}) }

  Process {
    id: probe
    stdout: StdioCollector {
      onStreamFinished: {
        let list
        try { list = JSON.parse(text) } catch (e) { return }
        if (!Array.isArray(list)) return
        root.allOutputs = list.map(m => ({
          name: m.name, description: m.description, disabled: m.disabled === true
        }))
      }
    }
  }

  Process {
    id: hypr
    // A compositor that is not there is not an error worth a toast: the shell
    // can run under a plain nested session while a page is being designed.
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn(`displays: ${text.trim()}`)
    }
  }
}
