import QtQuick
import QtQuick.Window
import qs.Common

// Self-check for Common/ToastCard's lifetime rules (run by tests/test-toasts.sh).
//
// Everything here is a thing that fails silently rather than visibly: a card
// that never goes away looks fine until you notice it is still there, and a
// card that goes away too early is only ever seen by whoever was aiming at its
// "delete" action. Three toasts share these rules now, so a regression here is
// three regressions.
Window {
  id: root
  visible: true
  width: 400; height: 200

  property int stepNo: 0
  property int autoTimeouts: 0
  property int neverTimeouts: 0

  // Throws rather than calling Qt.exit(): Qt.exit() only *schedules* the exit,
  // so the enclosing step runs on and the PASS line at the end of the last one
  // overwrites the failure. A harness that cannot fail is worse than none.
  function check(cond, msg) {
    if (!cond) throw new Error(msg)
  }

  // Does `item` have a direct child with this objectName? `children` is
  // ordered by z, not by declaration, so nothing here may index into it.
  function holds(item, name) {
    return item.children.some(c => c.objectName === name)
  }

  // The ordinary card: 60ms of life, then it asks to be dismissed.
  ToastCard {
    id: auto
    width: 300
    cardHeight: 40
    life: 60
    onTimeout: {
      root.autoTimeouts++
      auto.shown = false
    }

    Text { objectName: "slotted"; text: "content" }
  }

  // `life: 0` is the escalated update toast: it waits for an answer and must
  // never time out on its own.
  ToastCard {
    id: never
    width: 300
    cardHeight: 40
    life: 0
    onTimeout: root.neverTimeouts++
  }

  // Drives the checks that need real elapsed time. Each tick is one step.
  Timer {
    id: clock
    interval: 40
    repeat: true
    running: true
    onTriggered: root.advance()
  }

  function advance() {
    try {
      root.step()
    } catch (e) {
      console.warn(`FAIL: ${e.message}`)
      clock.stop()
      Qt.exit(1)
    }
  }

  function step() {
    root.stepNo++
    switch (root.stepNo) {
    case 1:
      // Hidden: no height at all, so the host Column closes the gap rather
      // than leaving a card-shaped hole between two toasts.
      root.check(!auto.visible, "a card with shown=false is visible")
      root.check(auto.implicitHeight === 0,
        `a hidden card claims ${auto.implicitHeight}px of height`)

      // The default slot puts content inside the glass, not beside it. A
      // default property alias is what makes that work, and if it ever stops
      // redirecting, every toast draws its text outside its own card.
      root.check(auto.children.length === 2,
        `the card root has ${auto.children.length} children, expected the shadow and the glass`)
      root.check(!root.holds(auto, "slotted"),
        "slotted content stayed on the card root instead of going into the glass")
      root.check(auto.children.some(c => root.holds(c, "slotted")),
        "slotted content did not land inside the glass panel")

      auto.shown = true
      never.shown = true
      break

    case 2:
      // ~40ms into a 60ms life: still up, and now it has a height.
      root.check(auto.visible, "a card with shown=true is not visible")
      root.check(auto.implicitHeight === 40,
        `a shown card is ${auto.implicitHeight}px tall, expected its cardHeight of 40`)
      root.check(root.autoTimeouts === 0, "the card timed out before its life ran out")

      // A second event while the card is still up never changes `shown`, so
      // only kick() can restart the clock. Without it the second toast would
      // inherit whatever was left of the first one's.
      auto.kick()
      break

    case 3:
      // ~40ms after the kick, so ~80ms after `shown` went true: had kick()
      // done nothing, the original 60ms would already have fired.
      root.check(root.autoTimeouts === 0,
        "kick() did not restart the countdown -- the card timed out on its first clock")
      break

    case 4:
      root.check(root.autoTimeouts === 1,
        `the card timed out ${root.autoTimeouts} times after its restarted life, expected once`)
      root.check(!auto.visible, "the card is still visible after its timeout was handled")
      break

    case 6:
      // Four ticks of a 60ms life and it has still never fired.
      root.check(root.neverTimeouts === 0,
        `life: 0 timed out ${root.neverTimeouts} times; it must wait for an answer`)
      root.check(never.visible, "the life: 0 card hid itself")

      clock.stop()
      console.warn("TOASTS-TEST-PASS")
      Qt.exit(0)
      break
    }
  }
}
