pragma Singleton
import Quickshell
import Quickshell.Hyprland

// The five session actions behind the power dropdown. Views call these; the
// exec lives here so no view has to own a Process.
Singleton {
  id: root

  // The launcher offers lock as well (the mockup puts it there), so the argv
  // is readable rather than written out twice.
  // c7shell-lock, not hyprlock: it draws the backdrop decoration the design
  // doc asks for and then execs hyprlock. It falls back to plain hyprlock on
  // any failure, so this stays the one call site either way.
  readonly property var lockArgv: ["c7shell-lock"]

  function lock() { Quickshell.execDetached(root.lockArgv) }

  // Hyprland parses dispatches as Lua here (docs/CONVENTIONS.md): the stock
  // "exit" dispatcher string is a syntax error, hl.dsp.exit() is the form that
  // works.
  function logout() { Hyprland.dispatch("hl.dsp.exit()") }

  function suspend() { Quickshell.execDetached(["systemctl", "suspend"]) }
  function reboot() { Quickshell.execDetached(["systemctl", "reboot"]) }
  function shutdown() { Quickshell.execDetached(["systemctl", "poweroff"]) }
}
