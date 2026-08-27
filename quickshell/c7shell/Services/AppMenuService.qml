pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Services

// Global menu model. GlobalMenuSlot only renders what `menus` holds.
//
// Nothing here talks DBus, because Quickshell 0.3.1 cannot: Quickshell.Io has
// no DBus binding, so the shell cannot own com.canonical.AppMenu.Registrar, and
// DBusMenuHandle is isCreatable:false, so QML cannot point one at a menu
// somebody else discovered. scripts/c7shell-appmenud.py is the registrar
// instead; it owns the name, reads each app's menu over com.canonical.dbusmenu
// and feeds it here as JSON lines over a unix socket.
//
// The join key is the PID. The registrar's `u windowId` is an X11 leftover with
// no meaning on Wayland, so the daemon resolves each caller's bus name to a PID
// and this end matches it against the focused Hyprland toplevel's
// lastIpcObject.pid. No daemon, no PID or no export -> `menus` is empty and the
// slot falls back to the window title, exactly as SP1 shipped.
Singleton {
  id: root

  readonly property var activeToplevel: ToplevelManager.activeToplevel

  // appId is often reverse-dns ("org.mozilla.firefox") -- last segment reads best.
  readonly property string appName: {
    const top = root.activeToplevel
    if (!top) return ""
    const id = top.appId ?? ""
    return id !== "" ? id.split(".").pop() : (top.title ?? "")
  }

  // The focused window's PID, or 0 while Hyprland has not answered a `clients`
  // query for it yet -- lastIpcObject is filled in from that, not from the
  // toplevel event.
  readonly property int activePid: Hyprland.activeToplevel?.lastIpcObject?.pid ?? 0

  // ...and that query only happens on demand, the same way CaptureOverlay has
  // to ask for one. A window opened after the shell started arrives with an
  // EMPTY lastIpcObject and its pid reads 0 for as long as it lives, so every
  // app launched into a running session would show no menus at all. Ask
  // whenever the focused window has no pid yet; `activePid` is a live binding
  // and re-evaluates when the answer lands.
  readonly property var hyprToplevel: Hyprland.activeToplevel
  onHyprToplevelChanged: {
    if (root.hyprToplevel && root.activePid === 0) Hyprland.refreshToplevels()
  }

  // pid -> menus, as the daemon last published it. REPLACED wholesale on every
  // update, never mutated in place: a binding on a var property does not
  // re-evaluate when the object it points at is edited underneath it.
  property var menuMap: ({})

  // [{ id, label, items: [{ id, label, shortcut, enabled, separator, submenu }] }]
  //
  // Plain JS objects on purpose, copied out of JSON. The exporting app can die
  // with its menu open, and a plain array cannot dangle the way a QsMenuEntry
  // owned by a dropped DBus connection would.
  //
  // Empty while the global menu is switched off (ShellStore.globalMenu): the
  // daemon has been told to drop the registrar by then, so whatever is still in
  // menuMap describes a bar no app is exporting to us any more.
  readonly property var menus: root.mockEnabled
    ? root.mockMenus
    : (ShellStore.globalMenu ? (root.menuMap[root.activePid] ?? []) : [])

  // The daemon turns `id` back into a com.canonical.dbusmenu Event("clicked")
  // on the exporting app. Mock items carry no id and only report themselves.
  function trigger(menuLabel, item) {
    if (!item || item.separator || item.enabled === false) return
    const sock = sockLoader.item
    if (item.id === undefined || !root.linked || !sock) return
    sock.write(JSON.stringify({ event: "trigger", pid: root.activePid, id: item.id }) + "\n")
    sock.flush()
  }

  // -- the switch ----------------------------------------------------------
  // Hiding the chips is only half of it. An app that finds
  // com.canonical.AppMenu.Registrar on the bus hands its menu bar over and
  // draws none of its own, so a shell that just stopped rendering would leave
  // dolphin (issue #17) with no menu at all. The daemon owns that name and this
  // is what tells it whether to -- see its "registrar" message.
  //
  // Only sent once ShellStore has read the file: the adapter's default is on,
  // and pushing that before the user's answer is known would flap the name on
  // every login for anyone who turned it off.
  function pushRegistrar() {
    const sock = sockLoader.item
    if (!ShellStore.ready || !root.linked || !sock) return
    sock.write(JSON.stringify({ event: "registrar", enabled: ShellStore.globalMenu }) + "\n")
    sock.flush()
  }

  Connections {
    target: ShellStore
    function onGlobalMenuChanged() { root.pushRegistrar() }
    // The link is usually up long before the file has been read.
    function onReadyChanged() { root.pushRegistrar() }
  }

  function ingest(line) {
    if (!line) return
    let msg
    try {
      msg = JSON.parse(line)
    } catch (e) {
      console.warn("appmenu: unparseable line from daemon:", line)
      return
    }
    const next = Object.assign({}, root.menuMap)
    if (msg.event === "menus") next[msg.pid] = msg.menus
    else if (msg.event === "gone") delete next[msg.pid]
    else return
    root.menuMap = next
  }

  // -- daemon link --
  readonly property string socketPath: {
    const dir = Quickshell.env("XDG_RUNTIME_DIR") ?? ""
    return dir !== "" ? `${dir}/c7shell-appmenu.sock` : ""
  }

  // Whether the daemon link is up. Everything reads this rather than the Socket,
  // which is replaced underneath it.
  readonly property bool linked: sockLoader.item?.connected ?? false

  // The socket is REBUILT to reconnect, never re-assigned. A Quickshell 0.3.1
  // Socket that has dropped is spent: assigning `connected = true` on it again
  // does nothing whatsoever, and neither does clearing and restoring `path`
  // (both measured -- the daemon could restart and the shell would never
  // reconnect for the rest of the session). Only a fresh object connects, so the
  // retry below discards this one and builds another.
  Component {
    id: sockComponent

    Socket {
      path: root.socketPath
      connected: true

      parser: SplitParser {
        splitMarker: "\n"
        onRead: line => root.ingest(line)
      }
    }
  }

  Loader {
    id: sockLoader
    // Only the initial value matters; the retry timer drives it from here on,
    // and socketPath never changes once the environment has been read.
    active: root.socketPath !== ""
    sourceComponent: sockComponent
  }

  // The daemon is autostarted beside the shell and can be restarted under it, so
  // a dropped link is normal, not fatal. Forget every menu on the way down: a
  // stale menu bar over a live window is worse than the title fallback.
  onLinkedChanged: {
    if (root.linked) {
      retry.interval = 1000
      // A restarted daemon comes up owning the registrar; tell it again.
      root.pushRegistrar()
    } else {
      root.menuMap = ({})
    }
  }

  // Reconnect with backoff, doubling to a 30s ceiling.
  Timer {
    id: retry
    running: root.socketPath !== "" && !root.linked
    repeat: true
    interval: 1000
    onTriggered: {
      sockLoader.active = false
      sockLoader.active = true
      retry.interval = Math.min(retry.interval * 2, 30000)
    }
  }

  // -- mock source --
  // Exercises the renderer with no daemon and no exporting app running.
  //   qs -c c7shell ipc call appmenu mock true
  property bool mockEnabled: false

  readonly property var mockMenus: [
    { label: "File", items: [
      { label: "New Tab", shortcut: "ctrl+t" },
      { label: "New Window", shortcut: "ctrl+n" },
      { label: "Private Window", shortcut: "ctrl+shift+p" },
      { separator: true },
      { label: "Settings", shortcut: "ctrl+," },
      { label: "Quit", shortcut: "ctrl+q" }
    ] },
    { label: "Edit", items: [
      { label: "Undo", shortcut: "ctrl+z" },
      { label: "Redo", shortcut: "ctrl+shift+z", enabled: false },
      { separator: true },
      { label: "Cut", shortcut: "ctrl+x" },
      { label: "Copy", shortcut: "ctrl+c" },
      { label: "Paste", shortcut: "ctrl+v" }
    ] },
    { label: "View", items: [
      { label: "Reload", shortcut: "ctrl+r" },
      { label: "Full Screen", shortcut: "f11" },
      { separator: true },
      { label: "Zoom In", shortcut: "ctrl++" },
      { label: "Zoom Out", shortcut: "ctrl+-" },
      { label: "Reset Zoom", shortcut: "ctrl+0" }
    ] },
    { label: "History", items: [
      { label: "Back", shortcut: "alt+left" },
      { label: "Forward", shortcut: "alt+right", enabled: false },
      { separator: true },
      { label: "Show All History", shortcut: "ctrl+shift+h" }
    ] },
    { label: "Help", items: [
      { label: "Keyboard Shortcuts", shortcut: "" },
      { label: "About", shortcut: "" }
    ] }
  ]

  IpcHandler {
    target: "appmenu"
    function mock(on: bool): void { root.mockEnabled = on }
    function state(): string {
      return `mock=${root.mockEnabled} enabled=${ShellStore.globalMenu} daemon=${root.linked} `
        + `pid=${root.activePid} `
        + `menus=${root.menus.length} known=${Object.keys(root.menuMap).join(",")}`
    }
  }
}
