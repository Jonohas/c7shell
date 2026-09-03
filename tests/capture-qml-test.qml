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
      console.log("CAPTURE-TEST-PASS")
      Qt.exit(0)
    })
  }
}
