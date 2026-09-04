import QtQuick
import qs.Services

// Self-check for the screenshot delay (run by tests/test-capture.sh).
//
// The countdown is the one part of the capture flow with no way to see itself
// go wrong: the overlay is unmapped for the whole of it, so a countdown that
// never ticks, ticks twice, or hands back to the shutter after it was
// cancelled all look identical from the desk -- nothing on screen, and then
// either a file or no file.
Window {
  id: root
  visible: true
  width: 240; height: 120

  // Every phase runs in the event loop rather than in one function, because
  // the second is what is under test. A thrown check therefore has to be
  // caught per phase, or it sits in the loop until the harness times out.
  function step(fn) {
    try {
      fn()
    } catch (e) {
      console.log("CAPTURE-TEST-FAIL: " + e.message)
      Qt.exit(1)
    }
  }

  function check(cond, msg) {
    if (!cond) throw new Error(msg)
  }

  property int elapsedCount: 0
  property var ticks: []

  Connections {
    target: CaptureService
    function onCountdownElapsed() { root.elapsedCount += 1 }
    function onCountdownChanged() { root.ticks = root.ticks.concat([CaptureService.countdown]) }
  }

  // The second half of a delayed capture: the shutter has already fired and
  // the overlay is selecting on the still it produced. Only the bookkeeping is
  // reachable here -- grim and the crop are processes -- but the bookkeeping is
  // what decides whether a full screenshot of the desktop is left in the
  // runtime dir, and whether the frame is still there to cut when it is.
  function frozenFrame() {
    root.check(CaptureService.frozen === "", "a frozen frame was set before anything froze one")
    root.check(String(CaptureService.frozenUrl) === "",
      `an empty frame still produced a url: "${CaptureService.frozenUrl}"`)

    CaptureService.frozen = "/run/user/1000/c7shell-freeze-1.png"
    // The overlay draws this with an Image, which needs a url and not a path.
    root.check(String(CaptureService.frozenUrl) === "file:///run/user/1000/c7shell-freeze-1.png",
      `the overlay would be handed "${CaptureService.frozenUrl}" to draw`)

    // cropFrozen claims the frame. The overlay closes immediately after
    // calling it, and closing discards whatever is still frozen -- so if the
    // claim does not happen, the capture deletes its own source.
    CaptureService.cropFrozen(0, 0, 10, 10)
    root.check(CaptureService.frozen === "",
      "cropping did not claim the frame, so the overlay's own close would delete it mid-crop")
    CaptureService.discardFrozen()
    root.check(CaptureService.frozen === "", "discarding a claimed frame put one back")

    // esc on the still: nothing is cut and the frame does not survive as a
    // full screenshot of the desktop sitting in the runtime dir.
    CaptureService.frozen = "/run/user/1000/c7shell-freeze-2.png"
    CaptureService.discardFrozen()
    root.check(CaptureService.frozen === "",
      "discarding left the frame in place; the next capture would draw this one")

    // Nothing frozen and something asks for a crop anyway.
    CaptureService.cropFrozen(0, 0, 10, 10)
    root.check(CaptureService.frozen === "", "cropping nothing invented a frame")
  }

  Component.onCompleted: root.step(() => {
    root.check(CaptureService.countdown === 0,
      "the countdown was already running before anything armed a capture")
    // The toolbar chip is labelled "3s". If these two ever disagree the chip
    // lies about how long you have.
    root.check(CaptureService.delaySeconds === 3,
      `the delay is ${CaptureService.delaySeconds}s but the chip says 3s`)

    CaptureService.startCountdown("DP-1")
    // Immediately, not one tick later: the pill is bound to this, so a zero
    // here is a second of blank screen after the overlay goes down.
    root.check(CaptureService.countdown === 3,
      `arming showed ${CaptureService.countdown} instead of the full delay`)
    // Latched at arm time, so the pill cannot follow the pointer to the other
    // output half way through -- the same reason FinishedToast latches.
    root.check(CaptureService.countdownMonitor === "DP-1",
      `the countdown did not latch the monitor it was armed on: "${CaptureService.countdownMonitor}"`)
    runOut.start()
  })

  Timer {
    id: runOut
    interval: 3600   // three real seconds plus slack; the tick is the subject
    onTriggered: root.step(() => {
      root.check(root.ticks.join(",") === "3,2,1,0",
        `the pill must show every second down to zero; it showed ${root.ticks.join(",")}`)
      root.check(root.elapsedCount === 1,
        `zero handed back to the shutter ${root.elapsedCount} times, not once`)

      root.ticks = []
      root.elapsedCount = 0
      CaptureService.startCountdown("DP-1")
      cancel.start()
    })
  }

  Timer {
    id: cancel
    interval: 1200
    onTriggered: root.step(() => {
      // What reopening the overlay does. Before the countdown existed this was
      // the whole bug: the pending capture was dropped in silence, and being
      // unable to see the delay at all is what made people reopen the overlay
      // to "retry" in the first place.
      CaptureService.cancelCountdown()
      root.check(CaptureService.countdown === 0,
        `cancelling left ${CaptureService.countdown} on the pill`)
      stayCancelled.start()
    })
  }

  Timer {
    id: stayCancelled
    interval: 2600   // well past where the cancelled countdown would have run out
    onTriggered: root.step(() => {
      root.check(root.elapsedCount === 0,
        "a cancelled countdown still reached the shutter -- that capture would be taken with the next session's geometry")
      root.check(CaptureService.countdown === 0,
        `the countdown restarted itself after being cancelled: ${CaptureService.countdown}`)
      root.frozenFrame()
      console.log("CAPTURE-TEST-PASS")
      Qt.exit(0)
    })
  }
}
