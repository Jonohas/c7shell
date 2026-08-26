pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.Services

// Screen recording via wf-recorder. The interface (active / paused / elapsed /
// elapsedText / start / stop / togglePause + the "recording" IPC target) is the
// one SP1's bar island already binds to; `finished` is additive, for the toast.
Singleton {
  id: root

  // The process IS the state. Tracking it by hand meant a wf-recorder that never
  // started left `active` true forever: QProcess emits no finished() on
  // FailedToStart, it emits errorOccurred, which QML cannot connect to -- so
  // onExited never ran and the island counted up over nothing.
  readonly property bool active: proc.running

  // wf-recorder cannot pause. It installs handlers for SIGINT/SIGTERM/SIGHUP
  // only, all of which end the recording -- there is no resume-able state to
  // enter. So `paused` never becomes true and togglePause() does nothing; the
  // island's pause control was dropped for that reason, but the property stays
  // because the interface is fixed and a live-reload back to the stub must bind.
  readonly property bool paused: false

  property int elapsed: 0

  signal finished(string path)

  readonly property string elapsedText: {
    const m = Math.floor(elapsed / 60), s = elapsed % 60
    return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
  }

  readonly property string dir: `${Quickshell.env("HOME")}/Videos`

  property real startedAt: 0

  // options (all optional): geometry "x,y wxh" · output monitor name ·
  // mic / sysAudio / fps60 booleans. start() with no argument records the
  // focused monitor with no audio, which is what the bare SP1 interface promised.
  function start(options) {
    // proc.running, not root.active: stop() only signals the recorder, and a
    // start inside the window before it actually exits would reassign the
    // command of a live Process -- the new recording never starts and the old
    // one's exit reports the new, nonexistent file.
    if (proc.running) {
      NotifServer.send("recording not started",
        "the previous recording is still closing its file")
      return
    }
    const o = options ?? ({})
    const file = `${root.dir}/recording-${Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")}.mp4`

    const args = ["-f", file, "-y"]
    // Without -g or -o wf-recorder asks which output to record on stdin and
    // then dies on the EOF it gets instead, so a bare start() has to name the
    // monitor the keybind came from.
    const output = o.output || Hyprland.focusedMonitor?.name || ""
    if (o.geometry) args.push("-g", o.geometry)
    else if (output !== "") args.push("-o", output)
    if (o.fps60) args.push("-r", "60")

    // wf-recorder takes exactly one --audio device, so mic and system audio are
    // mutually exclusive (the overlay's chips enforce that too).
    // ponytail: mixing both needs a pipewire null-sink + two loopbacks; add that
    // only if someone actually asks for commentary over system sound.
    if (o.mic) args.push("--audio=@DEFAULT_SOURCE@")
    else if (o.sysAudio) args.push("--audio=@DEFAULT_MONITOR@")

    // Carried on the Process, like CaptureService's shot.pending: the file this
    // run will report when it exits, immune to the next start() overwriting it.
    proc.pending = file
    proc.command = ["wf-recorder"].concat(args)
    proc.running = true

    root.startedAt = Date.now()
    root.elapsed = 0
    startCheck.restart()
  }

  // A process that never starts (no wf-recorder on PATH) emits errorOccurred,
  // not finished, and QML can connect to neither -- so onExited never runs and
  // nothing would ever say why the island failed to appear. `pending` is still
  // set means no exit was handled either.
  Timer {
    id: startCheck
    interval: 400
    onTriggered: {
      if (proc.running || proc.pending === "") return
      proc.pending = ""
      NotifServer.send("recording failed", "wf-recorder did not start")
    }
  }

  function stop() {
    if (!proc.running) return
    // SIGINT, not kill: it is wf-recorder's graceful path, which flushes the
    // encoder and closes the container. SIGKILL leaves an unplayable file.
    proc.signal(2)
  }

  function togglePause() { /* no-op -- see `paused` */ }

  Process {
    id: proc

    property string pending: ""

    stderr: StdioCollector { id: recErr }

    onExited: (code, status) => {
      const ran = root.elapsed
      root.elapsed = 0
      const file = proc.pending
      proc.pending = ""
      // SIGINT is how stop() ends a recording, and wf-recorder handles it and
      // exits 0 -- so a non-normal status here means it was killed outright and
      // the container was never closed. Reporting that file as finished would
      // hand the toast a truncated video.
      if (code === 0 && status === 0) {
        root.finished(file)
        return
      }
      const why = recErr.text.trim().split("\n").pop() || `wf-recorder exited ${code}`
      console.warn(`recording: ${why}: ${proc.command.join(" ")}`)
      // -y creates the container up front, so a run that got as far as encoding
      // leaves a truncated, unplayable mp4 behind. Not deleted -- a partial
      // recording of something unrepeatable is still worth more than a tidy
      // Videos folder -- but never left unmentioned either.
      const leftover = ran > 0
        ? `\n${file.substring(file.lastIndexOf("/") + 1)} is truncated and unplayable`
        : ""
      NotifServer.send("recording failed", why + leftover)
    }
  }

  // Wall clock, not a tick count: a stalled or throttled timer must not make the
  // island under-report how long the recording has been running.
  Timer {
    running: root.active
    interval: 1000
    repeat: true
    onTriggered: root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dir])

  IpcHandler {
    target: "recording"
    function toggle(): void { root.active ? root.stop() : root.start() }
  }
}
