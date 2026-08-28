pragma Singleton
import Quickshell
import QtQuick

// The OSD's whole state: one pill at a time, replace-in-place, no queue.
// A queue would replay every step of a held volume key long after the finger
// came off it, so show() overwrites what is on screen and restarts the clock.
Singleton {
  id: root

  // Kinds: volume · mute · mic · brightness · layout · workspace. `payload`
  // carries whatever that kind renders (see Modules/Osd). Both survive hide():
  // the pill window stays mapped through its fade-out, so clearing them there
  // would swap the content for the fallback glyph mid-fade. "" only before the
  // first show().
  property string kind: ""
  property var payload: ({})

  property bool showing: false

  function show(kind, payload) {
    root.payload = payload ?? ({})
    root.kind = kind
    root.showing = true
    hideTimer.restart()
  }

  function hide() {
    root.showing = false
  }

  Timer {
    id: hideTimer
    interval: 1200   // spec §4a: "hide after ~1.2s"
    onTriggered: root.hide()
  }
}
