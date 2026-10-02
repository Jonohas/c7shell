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
// Layout is implicit, the way KDE and GNOME do it: whatever set of screens is
// connected is a SETUP, and apply saves the whole arrangement under it in
// ~/.config/hypr/displays.json. conf/monitors.lua does the matching -- it alone
// sees the lid and the screens Hyprland hides once they are off -- and writes
// the setup it matched to displays-state.json, which is the key saved under
// here. Nothing here writes to conf/monitors.lua. Same two-sided-JSON pattern
// as appearance.json.
Singleton {
  id: root

  Component.onCompleted: root.probeAll()

  // Last spec applied per output, so a slider drag coalesces into one hyprctl
  // instead of one per frame.
  property var queued: ({})

  // -- saved setups ---------------------------------------------------------
  // The setup conf/monitors.lua matched, and the screens in it -- including
  // ones switched off, which Hyprland.monitors no longer lists. Empty until a
  // conf/monitors.lua that writes the state file has applied once; nothing is
  // saved until then, because a guessed key would never be looked up again.
  readonly property string signature: stateAdapter.setup ?? ""
  readonly property var screens: stateAdapter.screens ?? []

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

  // Save the WHOLE setup as it will be once the staged edits land, not just the
  // fields that changed: there is no hand-written layout underneath any more,
  // so a screen with no saved position would come back wherever auto put it.
  // Also refreshes the per-screen memory, so a panel carries its mode, scale
  // and rotation into a set of screens it has never been arranged in.
  // JsonAdapter only notices whole-property assignment, so rebuild rather than
  // mutate in place.
  function persist() {
    if (!root.ready || root.signature === "") return
    const layouts = Object.assign({}, root.layouts)
    const desk = Object.assign({}, layouts[root.signature])
    const outputs = Object.assign({}, adapter.outputs)

    for (const m of Hyprland.monitors.values) {
      const s = root.stagedFor(m.name)
      const f = root.persistable(Object.assign({
        position: `${m.x}x${m.y}`,
        mode: `${m.width}x${m.height}@${(m.lastIpcObject?.refreshRate ?? 0).toFixed(2)}`,
        scale: m.scale,
        transform: m.lastIpcObject?.transform ?? 0,
      }, s))
      // "auto" is not saved, and must not leave the old position behind either:
      // the next replug would put the screen straight back.
      if (s.position === "auto") delete f.position
      const panel = Object.assign({}, f)
      delete panel.position
      // Merged, not replaced: a hand-written bitdepth lives here too, and the
      // page has no control that would write it back.
      outputs[m.description] = Object.assign({}, outputs[m.description], panel)
      desk[m.description] = s.disabled === true ? Object.assign(f, { disabled: true }) : f
    }
    // Screens already off: in the setup, gone from Hyprland.monitors. Only the
    // on/off flag can change here; the rest is what was saved when it was on.
    for (const o of root.allOutputs) {
      if (!o.disabled || root.screens.indexOf(o.description) < 0) continue
      const entry = Object.assign({}, desk[o.description], { disabled: true })
      if (root.stagedFor(o.name).disabled === false) delete entry.disabled
      desk[o.description] = entry
    }

    layouts[root.signature] = desk
    adapter.layouts = layouts
    adapter.outputs = outputs
  }

  // Forget this setup, so the next reload comes back up with every screen on
  // and Hyprland's auto placement. A saved arrangement the user cannot clear
  // would be worse than no persistence at all.
  function forget() {
    if (!root.ready) return
    const layouts = Object.assign({}, root.layouts)
    delete layouts[root.signature]
    adapter.layouts = layouts
    // Forgetting is only half the answer -- the live layout is still whatever
    // was dragged. A reload re-runs conf/monitors.lua, which now finds nothing
    // saved and lays the desk out fresh, so the button does what it says.
    reload.restart()
  }

  // Written by conf/monitors.lua after every apply. Read-only on this side:
  // writing it back would fight the compositor for ownership of it.
  FileView {
    id: stateFile

    path: `${Quickshell.env("HOME")}/.config/hypr/displays-state.json`
    watchChanges: true
    // Absent until hyprland's first apply. Nothing is saved until it exists.
    printErrors: false

    onFileChanged: stateFile.reload()

    JsonAdapter {
      id: stateAdapter

      property string setup: ""
      property var screens: []
    }
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

      // { "<desc>|<desc>": { "<desc>": { position, mode, scale, transform, disabled } } }
      property var layouts: ({})
      // { "<desc>": { mode, scale, transform, bitdepth? } } -- per-screen memory.
      property var outputs: ({})
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
  // Disabling is saved with the setup, like every other edit. A setup that
  // would leave every screen off is refused twice: here, and by
  // conf/monitors.lua, which ignores one rather than black the desk out.
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
  // value; commit() saves the setup and replays each through apply(), which is
  // where the real hyprctl lives.
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
    root.persist()
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
