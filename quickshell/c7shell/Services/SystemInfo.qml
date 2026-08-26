pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Identity line for the power dropdown header (mockup 3a): "red@c7-desk" and
// "up 6h 12m".
Singleton {
  id: root

  readonly property string user: Quickshell.env("USER") ?? "user"
  readonly property string host: hostFile.text().trim() || "localhost"
  readonly property string userHost: `${root.user}@${root.host}`

  // /proc/uptime is read exactly once. The kernel counter and the wall clock
  // advance together, so re-reading the file every minute would buy nothing.
  property real bootSeconds: 0
  property real readAt: 0

  readonly property string uptimeText: {
    clock.date   // re-evaluate once a minute
    if (root.bootSeconds <= 0) return "up ?"
    const total = root.bootSeconds + (Date.now() - root.readAt) / 1000
    const d = Math.floor(total / 86400)
    const h = Math.floor(total / 3600) % 24
    const m = Math.floor(total / 60) % 60
    if (d > 0) return `up ${d}d ${h}h`
    return h > 0 ? `up ${h}h ${m}m` : `up ${m}m`
  }

  SystemClock { id: clock; precision: SystemClock.Minutes }

  FileView { id: hostFile; path: "/etc/hostname"; blockLoading: true; printErrors: false }
  FileView { id: uptimeFile; path: "/proc/uptime"; blockLoading: true; printErrors: false }

  Component.onCompleted: {
    root.bootSeconds = parseFloat(uptimeFile.text().split(" ")[0]) || 0
    root.readAt = Date.now()
  }
}
