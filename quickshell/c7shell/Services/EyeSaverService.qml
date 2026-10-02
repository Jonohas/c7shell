pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Eye saver: the warm-gamma (blue light filter) mode, for
// Modules/Settings/pages/DisplaysPage.qml.
//
// The gamma ramp belongs to hyprsunset, which holds it for as long as it runs
// and hands it back when it exits -- so "off" is simply not running it, and
// there is nothing to restore on logout or on a shell crash. It is an
// optdepends: without it the page says so and everything else carries on.
//
// A temperature change goes over hyprsunset's OWN ipc (via hyprctl) rather
// than by restarting it. Restarting drops the gamma to identity until the new
// process has mapped its ctm, which over a slider drag is a screen that
// flashes cold on every step -- the one thing the slider exists to let you judge.
Singleton {
  id: root

  // Kelvin. Below 2000 the screen is orange enough that text loses contrast;
  // 6500 IS daylight, i.e. no filter at all, so it is the top of the range
  // rather than a value worth staying on.
  readonly property int minTemperature: 2000
  readonly property int maxTemperature: 6500

  readonly property bool enabled: ShellStore.values.eyeSaver
  readonly property int temperature: ShellStore.values.eyeSaverTemperature

  // Only true once the probe has answered. Nothing is launched before then:
  // the point of the probe is to not spawn a command that is not installed.
  property bool available: false
  property bool probed: false

  function setEnabled(on) {
    ShellStore.values.eyeSaver = on
  }

  function setTemperature(k) {
    ShellStore.values.eyeSaverTemperature =
      Math.max(root.minTemperature, Math.min(root.maxTemperature, Math.round(k)))
  }

  Process {
    command: ["sh", "-c", "command -v hyprsunset >/dev/null 2>&1"]
    running: true
    onExited: code => {
      root.available = code === 0
      root.probed = true
    }
  }

  // -- the filter ------------------------------------------------------------
  // `running` stays a binding: the live temperature is pushed through
  // hyprctl below, so nothing here ever has to stop and start the process.
  Process {
    id: sunset

    command: ["hyprsunset", "-t", String(root.temperature)]
    running: ShellStore.ready && root.available && root.enabled

    stderr: SplitParser {
      onRead: line => { if (line.trim() !== "") console.warn("eye saver:", line) }
    }

    // A refusal to start (another ctm manager already holds the gamma) leaves
    // the toggle on with nothing behind it, which is worth a line in the log.
    onExited: code => {
      if (code !== 0 && root.enabled)
        console.warn(`eye saver: hyprsunset exited ${code}`)
    }
  }

  // -- live temperature ------------------------------------------------------
  // One hyprctl call per change, never a held-open socket: hyprsunset's ipc
  // thread keeps its event-loop mutex while it blocks reading a connection, so
  // a persistent client wedges the daemon and SIGTERM (the toggle turning off)
  // deadlocks instead of exiting. Calls are serialised so a slider drag cannot
  // land out of order; `command` reads the temperature as each one starts.
  property bool pushPending: false

  onTemperatureChanged: {
    if (!sunset.running) return
    if (push.running) root.pushPending = true
    else push.running = true
  }

  // Losing the race with a just-started daemon only costs the live push: the
  // start already carries -t.
  Process {
    id: push
    command: ["hyprctl", "hyprsunset", "temperature", String(root.temperature)]
    stdout: SplitParser {
      onRead: line => {
        if (line.trim() !== "" && line.trim() !== "ok") console.warn("eye saver:", line)
      }
    }
    onExited: {
      if (!root.pushPending) return
      root.pushPending = false
      if (sunset.running) push.running = true
    }
  }
}
