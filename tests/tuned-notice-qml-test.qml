import QtQuick
import QtQuick.Window
import qs.Services
import qs.Modules.Power

// Self-check for Modules/Power/TunedNotice (run by tests/test-tuned-notice.sh).
//
// The card the battery popover and the settings page both show when tuned is
// not running. It was the same card written out twice, a pixel apart, and the
// two copies had already started to answer differently -- so what this pins is
// the part that is not cosmetic: which of the two problems the card names, and
// whether it offers a button that can actually do something.
Window {
  id: root
  visible: true
  width: 400; height: 400

  function check(cond, msg) {
    if (!cond) throw new Error(msg)
  }

  // The button, wherever it sits in the column. Found by its own type rather
  // than by index: the column's children are the header row, the blurb and the
  // button, and a reordering is not what this test is about.
  function enableButton(notice) {
    const col = notice.children[0]
    return col.children[col.children.length - 1]
  }

  TunedNotice {
    id: page
    width: 320
    blurb: "the settings page's longer wording"
  }

  TunedNotice {
    id: popover
    width: 236
    compact: true
    blurb: "the popover's shorter wording"
  }

  Component.onCompleted: {
    // -- tuned is installed but stopped: a button that can fix it ------------
    TunedService.installed = true

    check(!page.compact, "the page card defaulted to compact")
    check(enableButton(page).visible,
          "tuned is installed and stopped, but the card offers no way to start it")
    check(enableButton(popover).visible,
          "the popover card offers no way to start a stopped tuned")

    // Full width in the popover, hugging its label on the page. A panel-wide
    // button in a settings column reads as a section rather than an action,
    // which is the one metric the two callers genuinely disagree about.
    check(enableButton(popover).width === popover.children[0].width,
          `the popover's button is ${enableButton(popover).width}px across a ${popover.children[0].width}px column, not full width`)
    check(enableButton(page).width < page.children[0].width,
          "the page's button spans the whole column instead of hugging its label")

    // -- tuned is not installed: no button, because there is nothing to start -
    TunedService.installed = false
    check(!enableButton(page).visible,
          "tuned is not installed, but the card still offers to start the service")
    check(!enableButton(popover).visible,
          "the popover card offers to start a service that is not installed")

    // Both cards still say something, and the caller's wording is what they
    // say -- the blurb is the one line the two callers do not share.
    check(page.blurb !== popover.blurb,
          "the two callers ended up with the same blurb, so the property is not being read")
    check(page.implicitHeight > 0 && popover.implicitHeight > 0,
          "a card collapsed to nothing")

    console.log("TUNED-NOTICE-TEST-PASS")
    Qt.exit(0)
  }
}
