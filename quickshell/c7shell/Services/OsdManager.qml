pragma Singleton
import Quickshell
import QtQuick

// The OSD's whole state: one pill at a time, replace-in-place, no queue.
// A queue would replay every step of a held volume key long after the finger
// came off it, so show() overwrites what is on screen and restarts the clock.
Singleton {
  id: root

  // Kinds: volume · mute · mic · brightness · layout · workspace · track.
  // `payload` carries whatever that kind renders (see Modules/Osd). Both
  // survive hide(): the pill window stays mapped through its fade-out, so
  // clearing them there would swap the content for the fallback glyph mid-fade.
  // "" only before the first show().
  property string kind: ""
  property var payload: ({})

  property bool showing: false

  // spec §4a: "hide after ~1.2s", which is the right length for a pill you
  // raised yourself by pressing a key and are already looking at.
  readonly property int defaultDuration: 1200

  // `duration` is optional and almost always omitted. The track-change pill
  // (15b) is the exception at 2.5s: nobody asked for it, so it has to survive
  // long enough to be noticed and read, which a volume step does not.
  function show(kind, payload, duration) {
    root.payload = payload ?? ({})
    root.kind = kind
    root.showing = true
    hideTimer.interval = duration > 0 ? duration : root.defaultDuration
    hideTimer.restart()
  }

  function hide() {
    root.showing = false
  }

  Timer {
    id: hideTimer
    // Set by every show(); this is only what it holds before the first one.
    interval: root.defaultDuration
    onTriggered: root.hide()
  }
}
