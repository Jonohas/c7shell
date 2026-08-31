import QtQuick
import QtQuick.Window
import osdtest

// Self-check for OsdManager (run by tests/test-osd.sh). The pill window stays
// mapped through its 150ms fade-out (OsdPill.qml keeps `visible` up while
// opacity > 0), so whatever `kind`/`payload` hold during the fade is what the
// user sees. hide() must therefore only drop `showing`; resetting `kind`
// mid-fade swaps the workspace pip for the fallback audio glyph for a frame.
Window {
  id: root
  visible: true
  width: 100; height: 100

  // Throws rather than calling Qt.exit(): Qt.exit() only *schedules* the exit,
  // so the enclosing function runs on and prints the PASS line regardless of
  // what the check found. Every assertion here was inert until this changed.
  function check(cond, msg) {
    if (!cond) throw new Error(msg)
  }

  Component.onCompleted: {
    try {
    OsdManager.show("workspace", { value: 3, hint: "super+3" })
    check(OsdManager.showing, "show() did not raise the pill")
    check(OsdManager.kind === "workspace", "show() did not set kind")
    check(OsdManager.payload.value === 3, "show() did not set payload")

    OsdManager.hide()
    check(!OsdManager.showing, "hide() left the pill showing")
    check(OsdManager.kind === "workspace",
      "hide() reset kind to '" + OsdManager.kind + "' -- the fade-out now renders the fallback audio glyph")
    check(OsdManager.payload.value === 3, "hide() reset payload")

    OsdManager.show("volume", { value: 40 })
    check(OsdManager.showing, "re-show after hide() did not raise the pill")
    check(OsdManager.kind === "volume", "re-show did not replace kind")

    // Arm the expiry test: the hideTimer fires 1200ms after this show().
    OsdManager.show("workspace", { value: 5 })
    } catch (e) {
      console.error("ASSERT-FAILED: " + e.message)
      Qt.exit(1)
    }
  }

  // The rest runs on a clock, because a duration can only be checked by
  // outliving it. Each step arms the next.
  Timer {
    id: defaultExpiry
    interval: 2000   // past the 1200ms default
    running: true
    onTriggered: {
      try {
      root.check(!OsdManager.showing, "the hide timer never fired")
      root.check(OsdManager.kind === "workspace",
        "timer expiry reset kind to '" + OsdManager.kind + "' -- the fade-out now renders the fallback audio glyph")

      // 15b's track pill asks for 2.5s, which is why show() takes a duration
      // at all. Nobody pressed a key to raise this one, so it has to outlast
      // the 1.2s a volume step gets.
      OsdManager.show("track", { title: "a song", artist: "somebody" }, 2500)
      root.check(OsdManager.showing, "show() with a duration did not raise the pill")
      root.check(OsdManager.payload.title === "a song", "the track payload did not survive show()")
      longStillUp.start()
      } catch (e) {
        console.error("ASSERT-FAILED: " + e.message)
        Qt.exit(1)
      }
    }
  }

  Timer {
    id: longStillUp
    interval: 1600   // past the default 1200, well short of 2500
    onTriggered: {
      try {
      root.check(OsdManager.showing,
        "a 2500ms pill was gone after 1600ms -- show()'s duration was ignored and the default was used")
      longExpiry.start()
      } catch (e) {
        console.error("ASSERT-FAILED: " + e.message)
        Qt.exit(1)
      }
    }
  }

  Timer {
    id: longExpiry
    interval: 1200   // 2800ms into the 2500ms pill
    onTriggered: {
      try {
      root.check(!OsdManager.showing, "the 2500ms pill never expired")

      // The duration is per-show, not sticky. Assigning the Timer's interval
      // breaks the binding that held the default, so a show() without a
      // duration has to put it back -- otherwise every volume step after one
      // track change lingers for 2.5s.
      OsdManager.show("volume", { value: 40 })
      backToDefault.start()
      } catch (e) {
        console.error("ASSERT-FAILED: " + e.message)
        Qt.exit(1)
      }
    }
  }

  Timer {
    id: backToDefault
    interval: 1600   // past 1200, short of 2500
    onTriggered: {
      try {
      root.check(!OsdManager.showing,
        "a show() with no duration kept the previous one's 2500ms -- the duration is sticky")
      console.log("OSD-TEST-PASS")
      Qt.exit(0)
      } catch (e) {
        console.error("ASSERT-FAILED: " + e.message)
        Qt.exit(1)
      }
    }
  }
}
