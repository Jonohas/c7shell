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

  // Hyprland raises `screencast` for every screencopy grab, including one-shot
  // screenshots (grim), so `active` waits out a debounce: a grab that ends
  // within the interval never lights the indicator.
  property bool active: false

  Timer {
    id: debounce
    interval: 400
    onTriggered: root.active = root.sessions > 0
  }

  onSessionsChanged: {
    if (sessions === 0) {
      debounce.stop()
      active = false
    } else if (!active) {
      debounce.restart()
    }
  }

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
