pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Simplified 6a: a count and a kernel flag, nothing else. checkupdates
// (pacman-contrib, sync-safe), paru -Qua for AUR, flatpak for apps; the
// three run as a chain so one Process each is enough.
Singleton {
  id: root

  property int pacman: 0
  property int aur: 0
  property int flatpak: 0
  readonly property int total: pacman + aur + flatpak
  property bool kernelPending: false
  property bool busy: false

  readonly property var kernels: ["linux", "linux-lts", "linux-zen", "linux-hardened"]

  function refresh() {
    if (root.busy) return
    root.busy = true
    pacProc.exec(["checkupdates", "--nocolor"])
  }

  Process {
    id: pacProc
    stdout: StdioCollector { id: pacOut }
    onExited: (code, status) => {
      // checkupdates: 0 = updates found, 2 = none, anything else = error
      const lines = code === 0
        ? pacOut.text.trim().split("\n").filter(l => l !== "") : []
      root.pacman = lines.length
      root.kernelPending = lines.some(l => root.kernels.includes(l.split(" ")[0]))
      if (code !== 0 && code !== 2)
        console.warn(`updates: checkupdates exited ${code}`)
      aurProc.exec(["paru", "-Qua"])
    }
  }
  Process {
    id: aurProc
    stdout: StdioCollector { id: aurOut }
    // paru -Qua exits nonzero when there is nothing to report; the text is
    // the signal, the exit code is not.
    onExited: () => {
      const t = aurOut.text.trim()
      root.aur = t === "" ? 0 : t.split("\n").length
      fpProc.exec(["flatpak", "remote-ls", "--updates", "--app", "--columns=application"])
    }
  }
  Process {
    id: fpProc
    stdout: StdioCollector { id: fpOut }
    onExited: () => {
      const t = fpOut.text.trim()
      root.flatpak = t === "" ? 0 : t.split("\n").length
      root.busy = false
    }
  }

  Timer {   // steady-state cadence
    interval: 30 * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }
  Timer {   // first check delayed past login so the network is up
    interval: 60 * 1000
    running: true
    onTriggered: root.refresh()
  }
}
