pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick

// Tracks portal screencast sessions via Hyprland's socket2 `screencast`
// event ("state,owner"). Note the event is not a session lifecycle signal --
// Hyprland derives it from each screencopy client's recent frame rate, so a
// live session toggles it off and on again whenever the frames slow down.
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
    id: rise
    interval: 400
    onTriggered: root.active = root.sessions > 0
  }

  // The event is a frame-rate heuristic, not a session state: Hyprland samples
  // each screencopy client twice a second and posts "0" whenever it took fewer
  // than a handful of frames in that window. A shared window on a workspace
  // nobody is looking at stops repainting and trips that constantly, so the
  // falling edge is held well past the sampling window -- clearing `active` on
  // the spot is what made the indicator flicker. The cost is an icon that
  // lingers a couple of seconds after a share really ends; for an indicator
  // that is the right way round.
  Timer {
    id: fall
    interval: 3000
    onTriggered: root.active = false
  }

  onSessionsChanged: {
    if (sessions === 0) {
      rise.stop()
      if (active) fall.restart()
    } else {
      fall.stop()
      if (!active) rise.restart()
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
    // Asked for explicitly: no reason to sit through the flicker hold-off.
    fall.stop()
    root.active = false
  }
}
