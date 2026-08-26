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
    onTriggered: Hyprland.refreshMonitors()
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
