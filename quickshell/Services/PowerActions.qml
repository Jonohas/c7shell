pragma Singleton
import Quickshell
import Quickshell.Hyprland

// The five session actions behind the power dropdown. Views call these; the
// exec lives here so no view has to own a Process.
Singleton {
  id: root

  function lock() { Quickshell.execDetached(["hyprlock"]) }

  // Hyprland parses dispatches as Lua here (docs/CONVENTIONS.md): the stock
  // "exit" dispatcher string is a syntax error, hl.dsp.exit() is the form that
  // works.
  function logout() { Hyprland.dispatch("hl.dsp.exit()") }

  function suspend() { Quickshell.execDetached(["systemctl", "suspend"]) }
  function reboot() { Quickshell.execDetached(["systemctl", "reboot"]) }
  function shutdown() { Quickshell.execDetached(["systemctl", "poweroff"]) }
}
