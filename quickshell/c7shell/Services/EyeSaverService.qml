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
// A temperature change goes over hyprsunset's OWN ipc socket rather than by
// restarting it. Restarting drops the gamma to identity until the new process
// has mapped its ctm, which over a slider drag is a screen that flashes cold
// on every step -- the one thing the slider exists to let you judge.
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
  // `running` stays a binding: the live temperature is pushed through the
  // socket below, so nothing here ever has to stop and start the process.
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
  readonly property string socketPath: {
    const dir = Quickshell.env("XDG_RUNTIME_DIR") ?? ""
    if (dir === "") return ""
    const sig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? ""
    return sig !== "" ? `${dir}/hypr/${sig}/.hyprsunset.sock` : `${dir}/hypr/.hyprsunset.sock`
  }

  onTemperatureChanged: {
    if (sunset.running) sock.item?.push()
  }

  // The socket only exists once the daemon has created it, and a Quickshell
  // Socket that failed to connect is spent (see AppMenuService for the same
  // finding), so it is rebuilt rather than reconnected. Losing the race only
  // costs the live push: the next start already carries -t.
  Component {
    id: sockComponent

    Socket {
      path: root.socketPath
      connected: true

      function push() {
        if (!connected) return
        write(`temperature ${root.temperature}\n`)
        flush()
      }

      // hyprsunset answers "ok" or an error string; nothing here acts on it,
      // but an unread reply would sit in the buffer forever.
      parser: SplitParser {
        splitMarker: "\n"
        onRead: line => {
          if (line.trim() !== "" && line.trim() !== "ok")
            console.warn("eye saver:", line)
        }
      }
    }
  }

  Loader {
    id: sock
    active: false
    sourceComponent: sockComponent
  }

  // Give the daemon a moment to bind before connecting, and drop the socket
  // with it so a stale one is never written to.
  Connections {
    target: sunset
    function onRunningChanged() {
      sock.active = false
      if (sunset.running) connect.restart()
    }
  }

  Timer {
    id: connect
    interval: 400
    onTriggered: sock.active = true
  }
}
