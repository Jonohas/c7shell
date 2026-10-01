pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// The enrolment sheet: one big print that fills in a ridge at a time as the
// reader records touches, over the dimmed settings window. Reparented to the
// window's contentItem for the same reason Dropdown is -- the page scrolls in
// a clipping Flickable, and a sheet sliced at the card edge is no sheet.
//
// The sheet starts the enrolment itself, so it is never open on a reader that
// is not listening; closing it while one runs cancels it.
Item {
  id: root

  property string finger: ""
  readonly property bool running: FingerprintService.enrolling !== ""
  readonly property bool done: FingerprintService.completed !== ""
                            && FingerprintService.completed === root.finger
  readonly property bool failed: !root.running && !root.done
                              && FingerprintService.error !== ""
  // A total is only known once busctl has answered; until then the print
  // fills against a typical reader's count rather than not at all.
  readonly property int total: FingerprintService.stages > 0 ? FingerprintService.stages : 10

  function open(finger) {
    root.finger = finger
    root.shown = true
    FingerprintService.enroll(finger)
  }

  function close() {
    if (root.running) FingerprintService.cancelEnroll()
    root.shown = false
  }

  property bool shown: false

  // The anchor stays out of the page's column -- only the overlay is drawn,
  // and it takes its visibility from the window it is reparented to.
  visible: false
  width: 0
  height: 0

  Connections {
    target: FingerprintService
    function onScanned() { glyph.tap() }
    function onRetried() { glyph.reject() }
  }

  Item {
    id: overlay
    parent: root.Window.contentItem ?? root
    anchors.fill: parent
    visible: root.shown
    z: 100

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)

      // The backdrop is not a dismiss: a stray click must not throw away
      // eight good scans.
      MouseArea { anchors.fill: parent }
    }

    GlassPanel {
      id: card
      anchors.centerIn: parent
      width: 300
      height: column.implicitHeight + 44
      radius: 20
      border.color: root.failed ? Theme.alpha(Theme.accent, 0.40) : Theme.hairlineStrong

      Column {
        id: column
        anchors {
          left: parent.left; right: parent.right; top: parent.top
          leftMargin: 22; rightMargin: 22; topMargin: 26
        }
        spacing: 0

        FingerprintGlyph {
          id: glyph
          anchors.horizontalCenter: parent.horizontalCenter
          size: 96
          fill: root.done ? 1 : Math.min(1, FingerprintService.scans / root.total)
          listening: root.running
          success: root.done
        }

        Item { width: 1; height: 20 }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.done ? `${FingerprintService.label(root.finger)} added`
              : root.failed ? "couldn't enroll"
              : `enroll ${FingerprintService.label(root.finger)}`
          font { family: Theme.fontMono; pixelSize: 13; weight: 600 }
          color: Theme.text
        }

        Item { width: 1; height: 6 }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: root.done ? "the lock screen takes it from the next lock"
              : FingerprintService.error !== "" ? FingerprintService.error
              : FingerprintService.hint !== "" ? FingerprintService.hint
              : FingerprintService.scans === 0 ? "rest your finger on the sensor"
              : "lift it and touch again, a little off-centre each time"
          font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
          lineHeight: 1.4
          color: root.failed ? Theme.accentSoft : Theme.alpha(Theme.text, 0.5)
        }

        Item { width: 1; height: 10 }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: !root.done
          text: FingerprintService.stages > 0
              ? `${FingerprintService.scans} of ${FingerprintService.stages}`
              : `${FingerprintService.scans} scans`
          font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
          color: Theme.alpha(Theme.text, 0.32)
        }

        Item { width: 1; height: 18 }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 8

          Chip {
            visible: root.failed
            text: "try again"
            accented: true
            onTriggered: root.open(root.finger)
          }

          Chip {
            text: root.done ? "done" : root.running ? "cancel" : "close"
            accented: root.done
            onTriggered: root.close()
          }
        }
      }
    }
  }
}
