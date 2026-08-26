pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick

// Tracks portal screencast sessions via Hyprland's socket2 `screencast`
// event ("state,owner", one event per session start/stop).
Singleton {
  id: root

  // ponytail: a bare counter; per-session identity would need the portal's
  // dbus. Clamped so a missed start event cannot wedge it negative.
  property int sessions: 0
  readonly property bool active: sessions > 0

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "screencast") return
      const on = event.data.split(",")[0] === "1"
      root.sessions = Math.max(0, root.sessions + (on ? 1 : -1))
    }
  }

  // No public API closes another app's portal session; bouncing the portal
  // drops every share. ponytail: fine on a single-user desktop.
  function stop() {
    Quickshell.execDetached(["systemctl", "--user", "restart",
      "xdg-desktop-portal-hyprland.service"])
    root.sessions = 0
  }
}
