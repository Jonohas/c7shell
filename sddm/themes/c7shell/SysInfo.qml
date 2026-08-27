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

  // The current network, published by the NetworkManager dispatcher script the
  // package installs (/usr/lib/NetworkManager/dispatcher.d/50-c7shell-greeter).
  // NetworkManager is only reachable over D-Bus, which QML cannot speak and the
  // sddm user would not be allowed to write to anyway -- so the dispatcher
  // writes what it knows to a file, as root, on every connection change. No
  // file means no pill: an empty name is the signal to hide it.
  // Overridable so the preview harness can point at a file it wrote; sddm
  // itself always gets the real one.
  property string networkFile: "/run/c7shell/network"
  property string networkName: ""
  property bool networkWireless: true
  property bool networkUp: false

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

  // Re-read on a timer as well as at startup: someone can walk into wifi range
  // while the greeter is sitting there, and a 4-line file every few seconds
  // costs nothing.
  property Timer networkPoll: Timer {
    interval: 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.readNetwork()
  }

  function readNetwork() {
    if (root.networkFile === "") return
    root.read(root.networkFile, function (text) {
      let name = "", kind = "wireless", state = "down"
      for (const line of text.split("\n")) {
        const eq = line.indexOf("=")
        if (eq < 1) continue
        const key = line.slice(0, eq), value = line.slice(eq + 1)
        if (key === "name") name = value
        else if (key === "kind") kind = value
        else if (key === "state") state = value
      }
      root.networkWireless = kind === "wireless"
      root.networkUp = state === "up"
      // A connection that is down is not a network the machine is "on", and the
      // greeter says nothing rather than something stale.
      root.networkName = root.networkUp ? name : ""
    })
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
