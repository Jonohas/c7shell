pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Services

// Everything the capture overlay is not allowed to do itself: overlay
// visibility state (so the one IPC target lives in one place, not once per
// screen), grim, wl-copy, and the toast's file actions.
Singleton {
  id: root

  readonly property string dir: `${Quickshell.env("HOME")}/Pictures/Screenshots`

  property bool overlayOpen: false

  signal captured(string path)
  // The toast owns the card, so it -- not this file -- decides when to drop it.
  // Emitted only once the file is really in the trash.
  signal discarded(string path)

  function open() { root.overlayOpen = true }
  function close() { root.overlayOpen = false }
  function toggle() { root.overlayOpen = !root.overlayOpen }

  // -- the toolbar's "3s" chip -------------------------------------------
  // The countdown lives here rather than on the overlay because the overlay is
  // unmapped for the whole of it -- it has to be, or grim would photograph the
  // dim -- so the seconds are drawn by CountdownPill, which is a different
  // surface and can only read shared state.
  readonly property int delaySeconds: 3
  property int countdown: 0
  // Latched at arm time, like FinishedToast's card: the pointer may leave the
  // output the capture was set up on, and the pill must not follow it.
  property string countdownMonitor: ""
  // Not "take the shot": the pill is still mapped at this point and the caller
  // owns the recomposite grace that gets it off the screen first.
  signal countdownElapsed()

  function startCountdown(monitor) {
    root.countdownMonitor = monitor
    root.countdown = root.delaySeconds
    ticker.restart()
  }

  function cancelCountdown() {
    ticker.stop()
    root.countdown = 0
  }

  Timer {
    id: ticker
    interval: 1000
    repeat: true
    onTriggered: {
      root.countdown -= 1
      if (root.countdown > 0) return
      ticker.stop()
      root.countdownElapsed()
    }
  }

  // geometry "x,y wxh" for region and window targets · output = a monitor name
  // for one screen · both empty = every screen.
  function shoot(geometry, output, copy) {
    // Dropping the second shot on the floor is the same §8 silence the rest of
    // this file exists to close: the overlay closed, the shutter did nothing,
    // and nothing said why. grim is a fraction of a second, so this only ever
    // fires on a genuine double-trigger.
    if (shot.running) {
      root.fail("screenshot skipped", "the previous capture is still writing")
      return
    }
    const file = `${root.dir}/shot-${Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")}.png`

    const grim = ["grim"]
    if (geometry) grim.push("-g", geometry)
    else if (output) grim.push("-o", output)
    grim.push(file)

    shot.pending = file
    shot.copy = copy
    shot.command = grim
    shot.running = true
  }

  // Queued, because both actions share one Process: exec() on a live one is
  // refused, so a quick "open" then "folder" used to discard whichever lost --
  // silently, since the discarded one never runs and never fails either.
  function openFile(path) { root.queueOpen(path) }

  function openFolder(path) {
    root.queueOpen(path.substring(0, path.lastIndexOf("/")))
  }

  function queueOpen(target) {
    openProc.queue = openProc.queue.concat([target])
    root.pumpOpen()
  }

  function pumpOpen() {
    if (openProc.running || openProc.queue.length === 0) return
    const next = openProc.queue[0]
    openProc.queue = openProc.queue.slice(1)
    openProc.exec(["xdg-open", next])
  }

  // gio trash rather than rm: a mis-click on the toast of a capture you just
  // took should be recoverable.
  function discard(path) {
    trashProc.pending = path
    trashProc.exec(["gio", "trash", path])
  }

  function shq(s) { return `'${String(s).replace(/'/g, "'\\''")}'` }

  function fail(what, why) {
    console.warn(`capture: ${what}: ${why}`)
    NotifServer.send(what, why)
  }

  Process {
    id: shot

    property string pending: ""
    property bool copy: false

    stderr: StdioCollector { id: shotErr }

    onExited: (code, status) => {
      if (code !== 0 || status !== 0) {
        root.fail("screenshot failed", shotErr.text.trim() || `grim exited ${code}`)
        return
      }
      // The PNG is written and it is good whatever the clipboard does next, so
      // the toast is raised first: coupling the two behind `&&` meant a wl-copy
      // failure swallowed the toast for a perfectly fine screenshot.
      root.captured(shot.pending)
      // grim writes either a file or stdout, never both, so the copy re-reads
      // the file just written. sh is here only for the redirect, and the one
      // value reaching it is quoted.
      if (shot.copy) copyProc.exec(["sh", "-c",
        `wl-copy --type image/png < ${root.shq(shot.pending)}`])
    }
  }

  Process {
    id: copyProc
    stderr: StdioCollector { id: copyErr }
    onExited: (code, status) => {
      if (code === 0 && status === 0) return
      root.fail("clipboard copy failed", copyErr.text.trim() || `wl-copy exited ${code}`)
    }
  }

  // The toast's actions. execDetached has no exit code at all: a gio trash that
  // failed left the file on disk while the toast said it was deleted.
  Process {
    id: openProc
    property var queue: []
    stderr: StdioCollector { id: openErr }
    onExited: (code, status) => {
      if (code !== 0 || status !== 0)
        root.fail("could not open", openErr.text.trim() || `xdg-open exited ${code}`)
      root.pumpOpen()
    }
  }

  Process {
    id: trashProc
    property string pending: ""
    stderr: StdioCollector { id: trashErr }
    onExited: (code, status) => {
      if (code === 0 && status === 0) {
        root.discarded(trashProc.pending)
        return
      }
      root.fail("could not delete", trashErr.text.trim() || `gio trash exited ${code}`)
    }
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dir])

  IpcHandler {
    target: "capture"
    function toggle(): void { root.toggle() }
  }
}
