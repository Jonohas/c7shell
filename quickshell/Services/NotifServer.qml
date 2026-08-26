pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// The shell owns org.freedesktop.Notifications: the calendar popover reads the
// real list instead of scraping another daemon. Any other daemon (dunst, mako)
// must be masked — the bus name has one owner and whoever asks first wins.
Singleton {
  id: root

  // trackedNotifications holds everything until it is dismissed, which is
  // exactly what the popover should list. Toasts are a shorter-lived view of
  // the same objects, so dismissing from either place removes it from both.
  readonly property var list: server.trackedNotifications
  readonly property int count: root.list.values.length

  // Suppresses toasts only. A notification that arrives during do-not-disturb
  // still lands in the list, which is the whole point of having a list.
  property bool dnd: false

  // Ids, never Notification objects. A Repeater copies its model into a list of
  // raw QObject*, and quickshell deletes a Notification the instant it closes —
  // the copy is then left holding a dangling pointer, and building the next set
  // of delegates dereferences it. An int cannot dangle, so delegates resolve
  // the object themselves via byId().
  property var popups: []

  // id -> epoch ms. The notification carries no timestamp of its own, and the
  // rows show "2m" / "1h".
  property var arrived: ({})

  // Bumped on a timer so the relative times re-evaluate. Callers pass it into
  // ago() so the dependency is visible at the binding site rather than hidden
  // inside the function.
  property int tick: 0

  readonly property int popupTimeout: 6000

  function byId(id) {
    return root.list.values.find(n => n.id === id) ?? null
  }

  // `tick` is unused on purpose — passing it is what makes a binding on this
  // call re-run once a minute.
  function ago(id, tick) {
    const ms = Date.now() - (root.arrived[id] ?? Date.now())
    const min = Math.floor(ms / 60000)
    if (min < 1) return "now"
    if (min < 60) return `${min}m`
    const hours = Math.floor(min / 60)
    if (hours < 24) return `${hours}h`
    return `${Math.floor(hours / 24)}d`
  }

  // The shell owns the bus name, so notify-send lands right back here: this is
  // how a service tells the user something failed instead of only console.warn.
  //
  // Every §8 failure path in the shell funnels through this one call, which is
  // why it cannot be execDetached: that reports nothing, so a missing
  // notify-send, or a reload window in which the shell does not own the bus
  // name, silently swallowed every failure message the shell had to give. One
  // at a time through a Process, and anything that does not land is shouted at
  // the log instead of vanishing.
  property var outbox: []

  function send(summary, body) {
    root.outbox = root.outbox.concat([[summary, body ?? ""]])
    root.pump()
  }

  function pump() {
    if (notify.running || root.outbox.length === 0) return
    const next = root.outbox[0]
    root.outbox = root.outbox.slice(1)
    notify.inFlight = `${next[0]} — ${next[1]}`
    notify.exec(["notify-send", "-a", "c7shell", next[0], next[1]])
    sendCheck.restart()
  }

  Process {
    id: notify

    // Non-empty means a message is out and unaccounted for.
    property string inFlight: ""
    stderr: StdioCollector { id: notifyErr }

    onExited: (code, status) => {
      sendCheck.stop()
      if (code !== 0 || status !== 0) {
        console.warn(`c7shell: NOTIFICATION UNDELIVERED: ${notify.inFlight} `
          + `(${notifyErr.text.trim() || `notify-send exited ${code}`})`)
      }
      notify.inFlight = ""
      root.pump()
    }
  }

  // A binary that is not on PATH never exits: QProcess emits errorOccurred, not
  // finished, and QML can connect to neither -- the same trap RecordingService's
  // startCheck exists for. Without this the outbox would stall forever on it.
  Timer {
    id: sendCheck
    interval: 2000
    onTriggered: {
      if (notify.running || notify.inFlight === "") return
      console.warn(`c7shell: NOTIFICATION UNDELIVERED: ${notify.inFlight} `
        + "(notify-send did not run)")
      notify.inFlight = ""
      root.pump()
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.count > 0
    onTriggered: {
      root.tick++
      // Neither map is keyed by anything that can clean itself up: dismiss(),
      // clearAll() and the expiry sweep all drop the notification and leave the
      // timestamp behind. Ids the server no longer knows are dead weight.
      const live = root.list.values.map(n => n.id)
      for (const key of Object.keys(root.arrived)) {
        if (live.includes(Number(key))) continue
        delete root.arrived[key]
        delete root.popupExpiry[key]
      }
    }
  }

  // Expiry is owned here rather than by a Timer inside the toast delegate.
  // Reassigning `popups` regenerates every delegate, so a delegate-owned timer
  // was restarted every time another notification arrived, and a steady trickle
  // meant no toast ever expired.
  property var popupExpiry: ({})

  Timer {
    interval: 500
    repeat: true
    running: root.popups.length > 0

    onTriggered: {
      const now = Date.now()
      const keep = root.popups.filter(id => {
        // Already gone from the server — closed by the app that sent it, or
        // dismissed from the popover. The toast goes with it.
        if (!root.byId(id)) return false
        return (root.popupExpiry[id] ?? 0) > now
      })

      // Only write when something actually left, or this regenerates the whole
      // stack twice a second.
      if (keep.length !== root.popups.length) root.popups = keep
    }
  }

  NotificationServer {
    id: server

    // Survive a shell reload rather than dropping whatever is unread.
    keepOnReload: true

    actionsSupported: true
    bodySupported: true
    bodyMarkupSupported: true
    imageSupported: true
    persistenceSupported: true

    onNotification: notification => {
      // Stamped before tracking: setting `tracked` builds the list row, and a
      // row created before its timestamp exists would read "now" forever.
      root.arrived[notification.id] = Date.now()

      // Nothing is tracked unless the server is told to; that is what turns a
      // fire-and-forget notification into a list entry.
      notification.tracked = true

      // Carried over from before a reload: it belongs in the list but it has
      // already been on screen once, so it must not toast again.
      if (notification.lastGeneration) return
      // The shell's own failure notices are exempt: send() is the §8 channel,
      // and do-not-disturb silencing the shell telling you why something broke
      // makes the never-silent rule a lie whenever the toggle is on.
      if (root.dnd && notification.appName !== "c7shell") return

      // Critical notifications are exempt from nothing else, but they do get
      // the same 6s as the rest — the list is the durable copy.
      root.popupExpiry[notification.id] = Date.now() + root.popupTimeout
      root.popups = [notification.id, ...root.popups]
    }
  }

  // Deferred by one event loop turn. These are called from a card's own click
  // handler, and mutating the model synchronously destroys the delegate that is
  // still executing. Qt.callLater lets the handler return first. The id is read
  // now rather than inside the closure: dismiss() destroys the notification, so
  // by the time the deferred call runs `n` may already be null.
  function unpop(n) {
    const id = n?.id
    Qt.callLater(() => { root.popups = root.popups.filter(p => p !== id) })
  }

  function dismiss(n) {
    const id = n?.id
    Qt.callLater(() => {
      root.popups = root.popups.filter(p => p !== id)
      if (n) n.dismiss()
    })
  }

  function clearAll() {
    Qt.callLater(() => {
      // The prune sweep below only runs while there are notifications, so
      // clearing them all is the one path that would strand every timestamp
      // until the next notification arrived. Nothing survives this, so neither
      // map has anything left to describe.
      root.arrived = ({})
      root.popupExpiry = ({})
      // Drop the toasts BEFORE dismissing. dismiss() destroys the notification
      // objects, and until popups is cleared every toast delegate is still
      // bound to one — the same dangling-delegate crash, reached by destroying
      // the object instead of replacing the model.
      root.popups = []
      // Copy first: dismiss() mutates trackedNotifications while it is iterated.
      for (const n of [...root.list.values]) n.dismiss()
    })
  }

  // Opening the notification list is itself an acknowledgement: everything on
  // screen is in it, so the toasts have done their job.
  function unpopAll() {
    Qt.callLater(() => { root.popups = [] })
  }

  // Turning dnd on clears what is on screen -- except the shell's own failure
  // notices, which onNotification lets through in the first place.
  onDndChanged: if (root.dnd) Qt.callLater(() => {
    root.popups = root.popups.filter(id => root.byId(id)?.appName === "c7shell")
  })
}
