pragma Singleton
import Quickshell
import QtQuick

// The OSD's whole state: one pill at a time, replace-in-place, no queue.
// A queue would replay every step of a held volume key long after the finger
// came off it, so show() overwrites what is on screen and restarts the clock.
Singleton {
  id: root

  // "" = nothing on screen. Kinds: volume · mute · mic · brightness · layout ·
  // workspace. `payload` carries whatever that kind renders (see Modules/Osd).
  property string kind: ""
  property var payload: ({})

  readonly property bool showing: root.kind !== ""

  function show(kind, payload) {
    root.payload = payload ?? ({})
    root.kind = kind
    hideTimer.restart()
  }

  function hide() {
    root.kind = ""
  }

  Timer {
    id: hideTimer
    interval: 1200   // spec §4a: "hide after ~1.2s"
    onTriggered: root.hide()
  }
}
