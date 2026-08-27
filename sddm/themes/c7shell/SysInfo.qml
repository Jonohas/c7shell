import QtQuick

// The top-left readout: hostname, distro, kernel. sddm gives the greeter no
// system information beyond the hostname, and there is no Quickshell.Io here to
// run a process with -- but XMLHttpRequest reads file:// URLs, and /proc and
// /etc/os-release are world-readable, so the two lines the mockup shows are
// available without adding a dependency.
QtObject {
  id: root

  property string kernel: ""
  property string distro: ""
  // 0-100, or -1 when the machine has no battery (every desktop).
  property int batteryLevel: -1
  property bool batteryCharging: false

  function read(path, ok) {
    const xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      // A file:// read reports status 0 on success, 404 when absent.
      if (xhr.status === 200 || xhr.status === 0) {
        if (xhr.responseText !== "") ok(xhr.responseText)
      }
    }
    try {
      xhr.open("GET", "file://" + path)
      xhr.send()
    } catch (e) {
      // An unreadable path is not worth a warning: the line just stays empty.
    }
  }

  Component.onCompleted: {
    // "Linux version 6.16.4-arch1-1 (linux@archlinux) ..." -> "6.16.4-arch1-1"
    root.read("/proc/version", function (text) {
      const m = text.match(/^Linux version (\S+)/)
      if (m) root.kernel = m[1]
    })
    root.read("/etc/os-release", function (text) {
      const m = text.match(/^NAME="?([^"\n]+)"?/m)
      if (m) root.distro = m[1].toLowerCase()
    })
    // BAT0 on nearly every laptop, BAT1 on a few ThinkPads. No globbing from
    // QML, so both are simply tried and whichever answers wins.
    for (const bat of ["BAT0", "BAT1", "macsmc-battery"]) {
      const base = "/sys/class/power_supply/" + bat
      root.read(base + "/capacity", function (text) {
        const n = parseInt(text.trim(), 10)
        if (!isNaN(n)) root.batteryLevel = n
      })
      root.read(base + "/status", function (text) {
        root.batteryCharging = text.trim() === "Charging"
      })
    }
  }
}
