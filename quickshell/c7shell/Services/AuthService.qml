pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Turn 14, service side: the one password prompt, for every caller.
//
// bin/c7-authd is the system half -- it registers as the session's polkit
// authentication agent and serves the socket bin/c7-askpass connects to for
// `sudo -A`. This file is its only reader, and Modules/Auth is its only view.
// See the daemon's header for the NDJSON both directions.
//
// The state machine is small because the daemon keeps it small: only the head
// of its queue is ever authenticating, so there is exactly one live
// conversation, one field, and one set of counters here at any time.
Singleton {
  id: root

  // -- what the daemon told us about itself ----------------------------------
  property bool ready: false
  // False when something else already holds the agent registration. The shell
  // stays out of the way rather than fighting for it -- and says so, because a
  // prompt that silently comes from a different program is the one thing this
  // whole design is against.
  property bool polkitOk: false
  property string userName: ""
  property string userGroup: ""

  // -- the queue -------------------------------------------------------------
  // Head first, exactly as the daemon ordered it.
  property var requests: []
  readonly property var current: root.requests.length > 0 ? root.requests[0] : null
  readonly property int waiting: Math.max(0, root.requests.length - 1)
  readonly property bool active: root.current !== null

  // -- the head's conversation -----------------------------------------------
  // ask · verifying · wrong · factor. There is no "idle": `active` is that.
  property string stage: "ask"
  property int tries: 0
  property int maxTries: 3
  // The PAM prompt, verbatim. Shown instead of "password" when PAM asks for
  // something else -- a token, a second factor -- because at that point the
  // only honest label is the one PAM wrote.
  property string promptText: ""
  // Nothing may be typed until PAM has actually asked for something. A field
  // that accepts a password before there is a prompt to answer sends it into
  // the next question instead of this one.
  property bool promptReady: false
  property string factorKind: ""
  property string factorText: ""
  // PAM_TEXT_INFO. Not decoration: pam_faillock says "the account is locked
  // due to 3 failed logins" through this and nothing else, and a prompt that
  // swallows that just looks like a password that has stopped working.
  property string noticeText: ""
  property string pamError: ""

  readonly property bool verifying: root.stage === "verifying"
  readonly property bool failed: root.stage === "wrong"
  // The design's rule: "use password" is always present on an alternate
  // factor, so it is never a dead end.
  readonly property bool onFactor: root.stage === "factor" && root.factorKind !== ""

  signal shake

  // -- what the view calls ---------------------------------------------------
  function submit(secret) {
    if (!root.current || !root.promptReady || root.verifying) return
    root.stage = "verifying"
    root.promptReady = false
    root.send({ cmd: "respond", id: root.current.id, secret: secret })
  }

  function cancel() {
    if (!root.current) return
    root.send({ cmd: "cancel", id: root.current.id })
  }

  // Leaves the fingerprint state for the password field. It does not tell PAM
  // anything -- there is no way to un-offer a factor mid-conversation -- it
  // reveals the field so the password prompt sitting behind the fingerprint in
  // the PAM stack can be answered. Where there is no such prompt the field
  // stays locked, which is the honest picture: the reader is still the only
  // way in until it gives up on its own.
  function usePassword() {
    if (root.stage !== "factor") return
    root.stage = "ask"
  }

  function send(obj) {
    if (!daemon.running) return
    daemon.write(JSON.stringify(obj) + "\n")
  }

  // -- events ----------------------------------------------------------------
  function onEvent(ev) {
    switch (ev.ev) {
    case "ready":
      root.ready = true
      root.polkitOk = ev.polkit === true
      root.userName = ev.user ?? ""
      root.userGroup = ev.group ?? ""
      root.attempts = 0
      if (!root.polkitOk)
        console.warn("auth: another polkit agent holds the registration; "
                     + "c7shell will not draw polkit prompts")
      break

    case "request":
      root.requests = root.requests.concat([ev])
      break

    case "active":
      // A fresh head: everything the previous one accumulated is not ours.
      root.stage = "ask"
      root.tries = 0
      root.promptText = ""
      root.promptReady = false
      root.factorKind = ""
      root.factorText = ""
      root.noticeText = ""
      root.pamError = ""
      break

    case "prompt":
      root.promptText = ev.text ?? ""
      root.promptReady = true
      // A prompt arriving after a failure keeps the failure on screen: the
      // count is what tells someone they are running out of attempts, and it
      // has to survive the new PAM session that asks again.
      root.stage = root.tries > 0 ? "wrong" : "ask"
      break

    case "factor":
      root.factorKind = ev.kind ?? ""
      root.factorText = ev.text ?? ""
      root.stage = "factor"
      break

    case "info":
      root.noticeText = ev.text ?? ""
      break

    case "pamerror":
      root.pamError = ev.text ?? ""
      break

    case "failed":
      root.tries = ev.tries ?? (root.tries + 1)
      root.maxTries = ev.max ?? root.maxTries
      root.stage = "wrong"
      root.promptReady = false
      root.shake()
      break

    case "close":
      root.requests = root.requests.filter(r => r.id !== ev.id)
      break
    }
  }

  // -- the daemon ------------------------------------------------------------
  property int attempts: 0

  Process {
    id: daemon
    command: ["c7-authd"]
    running: true
    stdinEnabled: true

    stdout: SplitParser {
      onRead: line => {
        if (line.trim() === "") return
        try {
          root.onEvent(JSON.parse(line))
        } catch (e) {
          console.warn("auth: unparseable event line:", line)
        }
      }
    }
    // Not collected into a property: the daemon's stderr is diagnostics, and
    // anything it says about a failure is worth having in the shell's log
    // rather than in a string nothing reads.
    stderr: SplitParser {
      onRead: line => { if (line.trim() !== "") console.warn("auth:", line) }
    }

    onExited: code => {
      // Everything on screen belonged to a process that is gone.
      root.requests = []
      root.ready = false
      root.polkitOk = false
      root.attempts += 1
      restart.restart()
      if (code !== 0)
        console.warn(`auth: c7-authd exited ${code} (attempt ${root.attempts})`)
    }
  }

  // Backs off rather than spinning: a daemon that cannot start -- no
  // python-gobject, no polkit -- would otherwise be relaunched forever.
  Timer {
    id: restart
    interval: Math.min(30000, 500 * Math.pow(2, Math.min(root.attempts, 6)))
    onTriggered: {
      if (root.attempts === 3) root.fallback()
      daemon.running = true
    }
  }

  // Three failures to start means this machine cannot authenticate anything
  // through the shell -- and with c7shell's own agent not registered, nothing
  // else is offering to either. hyprpolkitagent is a depends= for exactly this
  // moment: an unstyled dialog is worth having when the alternative is a
  // desktop where pkexec silently does nothing.
  function fallback() {
    console.warn("auth: c7-authd will not start; falling back to hyprpolkitagent")
    fallbackProc.running = true
  }

  Process {
    id: fallbackProc
    command: ["/usr/lib/hyprpolkitagent/hyprpolkitagent"]
    stderr: SplitParser {
      onRead: line => { if (line.trim() !== "") console.warn("auth fallback:", line) }
    }
  }
}
