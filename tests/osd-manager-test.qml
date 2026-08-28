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

  function check(cond, msg) {
    if (cond) return
    console.error("ASSERT-FAILED: " + msg)
    Qt.exit(1)
  }

  Component.onCompleted: {
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
  }

  Timer {
    interval: 2000   // past the 1200ms hideTimer
    running: true
    onTriggered: {
      root.check(!OsdManager.showing, "the hide timer never fired")
      root.check(OsdManager.kind === "workspace",
        "timer expiry reset kind to '" + OsdManager.kind + "' -- the fade-out now renders the fallback audio glyph")
      console.log("OSD-TEST-PASS")
      Qt.exit(0)
    }
  }
}
