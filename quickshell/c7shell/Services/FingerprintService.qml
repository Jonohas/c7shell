pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Enrolled fingers, through fprintd's own CLI.
//
// fprintd is the store both unlock paths read: hyprlock talks to it over D-Bus
// (c7shell-lock switches that on once fprintd-list shows a finger), and the
// password prompt reaches it through pam_fprintd in polkit's PAM stack, which
// c7shell-bootstrap adds. So this only has to list, enroll and delete -- there
// is no c7shell-side copy of the list to keep in step.
//
// Enroll and delete are fprintd's net.reactivated.fprint.device.enroll action,
// so polkit asks first, and that question is the shell's own prompt.
Singleton {
  id: root

  // fprintd's finger names, in its own order. The label is the name with the
  // dashes spaced out, which is all "right-index-finger" needs.
  readonly property var fingers: [
    "left-thumb", "left-index-finger", "left-middle-finger",
    "left-ring-finger", "left-little-finger",
    "right-thumb", "right-index-finger", "right-middle-finger",
    "right-ring-finger", "right-little-finger"
  ]
  function label(finger) { return finger.replace(/-finger$/, "").replace(/-/g, " ") }

  readonly property string user: Quickshell.env("USER") ?? ""

  // False until fprintd-list has answered with a reader: no fprintd, no
  // reader and "not asked yet" all look the same to the page.
  property bool available: false
  property bool loaded: false
  property string device: ""
  property var enrolled: []
  readonly property var unenrolled: root.fingers.filter(f => !root.enrolled.includes(f))

  // Whether polkit's PAM stack offers the reader. Read, never written: /etc is
  // c7shell-bootstrap's to change.
  property bool promptOn: false

  // -- enrolment -------------------------------------------------------------
  property string enrolling: ""
  property int scans: 0
  // How many touches a full print takes on this reader -- fprintd's
  // num-enroll-stages, 13 on a Goodix MOC. 0 until it has been read, and the
  // sheet falls back to counting without a total.
  property int stages: 0
  // The finger the last enrolment finished, for the sheet's success state.
  property string completed: ""
  property string hint: ""
  property string error: ""
  readonly property bool busy: enrollProc.running || deleteProc.running

  // One per touch, so the glyph can animate the moment the reader reports
  // rather than when a counter happens to change.
  signal scanned
  signal retried

  function refresh() {
    listProc.running = true
    pamProc.running = true
  }

  function enroll(finger) {
    if (root.busy || !root.fingers.includes(finger)) return
    root.enrolling = finger
    root.completed = ""
    root.scans = 0
    root.hint = ""
    root.error = ""
    enrollProc.command = ["fprintd-enroll", "-f", finger]
    enrollProc.running = true
  }

  // Dropping the client is the cancel: fprintd releases a device whose
  // claimer leaves the bus, and the half-recorded print goes with it.
  function cancelEnroll() {
    root.enrolling = ""
    enrollProc.running = false
  }

  function remove(finger) {
    if (root.busy || !root.enrolled.includes(finger)) return
    root.error = ""
    deleteProc.command = ["fprintd-delete", root.user, "-f", finger]
    deleteProc.running = true
  }

  // fprintd-enroll's "Enroll result: <status>" lines, mapped to what the page
  // says. Anything not listed keeps the last hint: fprintd adds statuses.
  readonly property var retryHints: ({
    "enroll-retry-scan": "scan again",
    "enroll-swipe-too-short": "swipe too short, try again",
    "enroll-finger-not-centered": "finger not centred, try again",
    "enroll-remove-and-retry": "lift your finger and try again"
  })
  readonly property var failures: ({
    "enroll-failed": "enrolment failed",
    "enroll-data-full": "the reader has no room for another finger",
    "enroll-duplicate": "that finger is already enrolled",
    "enroll-disconnected": "the reader went away",
    "enroll-unknown-error": "the reader reported an error"
  })

  function onEnrollLine(line) {
    const m = line.match(/^Enroll result: (\S+)/)
    if (!m) {
      // Claim and polkit refusals arrive as plain text and a non-zero exit.
      if (/failed|error|not authorized/i.test(line)) root.error = line.trim()
      return
    }
    const status = m[1]
    if (status === "enroll-stage-passed") {
      root.scans += 1
      root.hint = ""
      root.scanned()
    } else if (status === "enroll-completed") {
      root.hint = ""
      root.completed = root.enrolling
      root.scanned()
    } else if (root.retryHints[status] !== undefined) {
      root.hint = root.retryHints[status]
      root.retried()
    } else if (root.failures[status] !== undefined) {
      root.retried()
      root.error = root.failures[status]
    }
  }

  // " - #0: right-index-finger" per finger; a reader with none says so in a
  // sentence, and a machine with no reader says "No devices available".
  function parseList(text) {
    const dev = text.match(/^Fingerprints for user \S+ on (.+?):?$/m)
              ?? text.match(/^User \S+ has no fingers enrolled for (.+?)\.?$/m)
    root.available = dev !== null
    root.device = dev ? dev[1] : ""
    // No String.matchAll in the QML engine.
    const found = []
    const row = /^\s*- #\d+: (\S+)/gm
    for (let m = row.exec(text); m !== null; m = row.exec(text)) found.push(m[1])
    root.enrolled = found
    root.loaded = true
    const path = text.match(/^Device at (\S+)/m)
    if (path && root.stages === 0) {
      stagesProc.command = ["busctl", "--system", "get-property", "net.reactivated.Fprint",
                            path[1], "net.reactivated.Fprint.Device", "num-enroll-stages"]
      stagesProc.running = true
    }
  }

  Component.onCompleted: root.refresh()

  Process {
    id: listProc
    command: ["fprintd-list", root.user]
    stdout: StdioCollector { id: listOut; onStreamFinished: root.parseList(listOut.text) }
    onExited: code => { if (code !== 0) root.parseList("") }
  }

  Process {
    id: stagesProc
    // busctl prints "i 13".
    stdout: SplitParser {
      onRead: line => {
        const n = parseInt(line.replace(/^i\s+/, ""), 10)
        if (n > 0) root.stages = n
      }
    }
  }

  Process {
    id: pamProc
    // /etc wins over the vendor copy, so that is the only file that can say yes.
    command: ["grep", "-qs", "pam_fprintd", "/etc/pam.d/polkit-1"]
    onExited: code => root.promptOn = code === 0
  }

  Process {
    id: enrollProc
    stdout: SplitParser { onRead: line => root.onEnrollLine(line) }
    stderr: SplitParser { onRead: line => root.onEnrollLine(line) }
    onExited: code => {
      if (code !== 0 && root.error === "" && root.enrolling !== "")
        root.error = "enrolment stopped"
      root.enrolling = ""
      root.hint = ""
      root.refresh()
    }
  }

  Process {
    id: deleteProc
    stderr: SplitParser { onRead: line => { if (line.trim() !== "") root.error = line.trim() } }
    onExited: root.refresh()
  }
}
