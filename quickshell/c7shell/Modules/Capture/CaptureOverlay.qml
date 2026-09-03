import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Theme
import qs.Services

// Mockups 5a (screenshot) and 5b (record). One fullscreen overlay for both,
// toggled by `qs -c c7shell ipc call capture toggle`.
//
// Focused monitor only. Covering every screen would mean one dim layer per
// output and a selection that can only live on one of them anyway; the focused
// output is where the pointer and the keybind came from.
PanelWindow {
  id: win

  // Latched, not bound. Hyprland's focused monitor follows the cursor, so a
  // live binding let the surface migrate to the other output mid-selection: the
  // rectangle was measured in the old frame, clampSelection() then clamped it to
  // the new output's bounds and geometryArg added the new origin, so the capture
  // was neither what was drawn nor where. It failed in silence because the
  // resulting geometry is still perfectly valid. FinishedToast latches for
  // exactly this reason.
  //
  // It tracks focus normally while the overlay is DOWN, so the value is already
  // correct at the instant it opens -- no re-latch has to win a race with the
  // `visible` binding below.
  property var mon: Hyprland.focusedMonitor

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() {
      if (!CaptureService.overlayOpen) win.mon = Hyprland.focusedMonitor
    }
  }

  // Never resolve to null. The name match fails whenever Hyprland's monitor
  // list and Quickshell's screen list disagree -- which they do after a
  // hotplug, since a reconnected output can come back under a different name
  // (DP-4 -> DP-3) and a config reload does not resync them. A null screen
  // means the window silently cannot map, while overlayOpen still flips true:
  // the overlay is then unreachable until the shell is restarted as a process.
  // Opening on the wrong output is recoverable; opening on none is not.
  screen: Quickshell.screens.find(s => s.name === win.mon?.name)
    ?? Quickshell.screens[0]
    ?? null

  anchors { top: true; left: true; right: true; bottom: true }
  // Ignore, not a zero zone: a zero zone reserves nothing but still RESPECTS the
  // bar's 48px reservation, so the surface started 48px down the screen while
  // geometryArg kept computing from the monitor's origin -- every region was
  // grabbed 48px above the rectangle drawn for it, and the top 48px could not be
  // selected at all.
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.namespace: "c7shell-capture"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  visible: CaptureService.overlayOpen

  // -- toolbar state --
  property string mode: "shot"          // shot | rec
  property string target: "region"      // region | window | screen | all
  property bool delayed: false          // the "3s" chip
  property bool copyToClipboard: true
  property bool mic: false
  property bool sysAudio: false
  property bool fps60: false

  // -- selection, in window-local logical pixels --
  property real selX: 0
  property real selY: 0
  property real selW: 0
  property real selH: 0
  readonly property bool hasSelection: selW >= 2 && selH >= 2

  // Compositor-global geometry is what grim and wf-recorder take, and both work
  // in the same logical coordinates Hyprland reports for monitors and clients.
  readonly property string geometryArg: {
    if (win.target === "screen" || win.target === "all") return ""
    if (!win.hasSelection) return ""
    const x = Math.round(win.selX + (win.mon?.x ?? 0))
    const y = Math.round(win.selY + (win.mon?.y ?? 0))
    return `${x},${y} ${Math.round(win.selW)}x${Math.round(win.selH)}`
  }

  // What the hint line says instead of its usual text, for a beat.
  property string notice: ""
  Timer { id: noticeLife; interval: 1600; onTriggered: win.notice = "" }

  onVisibleChanged: {
    if (!win.visible) {
      // Re-latch on the way down: focus may have moved while the overlay held
      // `mon` frozen, and the next open must not start in that stale frame.
      win.mon = Hyprland.focusedMonitor
      return
    }
    // A capture armed just before the overlay was reopened would otherwise fire
    // into this new session with the old session's geometry -- and a countdown
    // left running would arm it again a second later, so both go.
    fire.stop()
    CaptureService.cancelCountdown()
    win.notice = ""
    win.selW = 0
    win.selH = 0
    win.target = "region"
    // hyprctl's client list is only refreshed on demand, and a stale one would
    // snap the window target to geometry a window no longer has.
    Hyprland.refreshToplevels()
    keys.forceActiveFocus()
  }

  function toplevelsHere() {
    return Hyprland.toplevels.values.filter(t => {
      const o = t.lastIpcObject
      return o && o.mapped && !o.hidden && o.monitor === win.mon?.id
        && o.size && o.size[0] > 0 && o.size[1] > 0
    })
  }

  // Topmost = most recently focused. hyprctl's client order is not z-order, but
  // focusHistoryID is: 0 is the active window.
  function snapToWindowAt(x, y) {
    const gx = x + (win.mon?.x ?? 0), gy = y + (win.mon?.y ?? 0)
    let best = null
    for (const t of win.toplevelsHere()) {
      const o = t.lastIpcObject
      if (gx < o.at[0] || gy < o.at[1]) continue
      if (gx > o.at[0] + o.size[0] || gy > o.at[1] + o.size[1]) continue
      if (!best || o.focusHistoryID < best.focusHistoryID) best = o
    }
    if (!best) return
    win.selX = best.at[0] - (win.mon?.x ?? 0)
    win.selY = best.at[1] - (win.mon?.y ?? 0)
    win.selW = best.size[0]
    win.selH = best.size[1]
  }

  function selectWholeScreen() {
    win.selX = 0
    win.selY = 0
    win.selW = win.width
    win.selH = win.height
  }

  // A selection pushed past the edge (space-move, or a window hanging off the
  // output) makes grim error out and wf-recorder silently record the WHOLE
  // output instead -- "Bad geometry: %s, capturing whole output instead." So the
  // rectangle is kept on the surface rather than trusted to the tools.
  function clampSelection() {
    win.selW = Math.min(win.selW, win.width)
    win.selH = Math.min(win.selH, win.height)
    win.selX = Math.max(0, Math.min(win.selX, win.width - win.selW))
    win.selY = Math.max(0, Math.min(win.selY, win.height - win.selH))
  }

  // Hide first, capture after. The overlay is a layer surface like any other and
  // grim would otherwise photograph the dim and the toolbar.
  function arm() {
    // No rectangle means no capture. Falling through would silently grab the
    // whole default output instead, which is not what either target asked for --
    // and an overlay that just ignores ↵ is its own kind of silent failure, so
    // the hint says what is missing.
    if ((win.target === "region" || win.target === "window") && !win.hasSelection) {
      win.notice = win.target === "window" ? "hover a window first" : "drag a region first"
      noticeLife.restart()
      return
    }

    win.clampSelection()
    fire.geometry = win.geometryArg
    // wf-recorder records one output, so "all screens" in rec mode means the
    // focused one. Screenshots really can span every output, with no -o at all.
    fire.output = win.target === "screen" || (win.mode === "rec" && win.target === "all")
      ? (win.mon?.name ?? "")
      : ""
    fire.record = win.mode === "rec"

    CaptureService.close()
    // The 3s chip is a visible countdown, not a longer sleep: the pill draws
    // the seconds while the overlay is down and hands back here at zero.
    if (win.delayed && !fire.record)
      CaptureService.startCountdown(win.mon?.name ?? win.screen?.name ?? "")
    else
      fire.restart()
  }

  // Zero on the pill, not the shutter: the pill is a layer surface too, so it
  // needs the same recomposite grace the overlay does before grim reads the
  // screen -- which is exactly what `fire` is.
  Connections {
    target: CaptureService
    function onCountdownElapsed() { fire.restart() }
  }

  Timer {
    id: fire
    // Every capture waits this out, delayed or not: the overlay -- and the
    // countdown pill after it -- has to be unmapped and the frame
    // recomposited before grim reads the screen.
    interval: 150

    property string geometry: ""
    property string output: ""
    property bool record: false

    onTriggered: {
      if (fire.record) {
        RecordingService.start({
          geometry: fire.geometry,
          output: fire.output,
          mic: win.mic,
          sysAudio: win.sysAudio,
          fps60: win.fps60
        })
      } else {
        CaptureService.shoot(fire.geometry, fire.output, win.copyToClipboard)
      }
    }
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true

    property bool spaceHeld: false

    Keys.onEscapePressed: CaptureService.close()
    Keys.onReturnPressed: win.arm()
    Keys.onEnterPressed: win.arm()
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Space) { keys.spaceHeld = true; event.accepted = true }
    }
    Keys.onReleased: event => {
      if (event.key === Qt.Key_Space) { keys.spaceHeld = false; event.accepted = true }
    }

    Rectangle {   // the dim
      anchors.fill: parent
      // Mockup 5a says rgba(4,4,6,.6); Theme.bg is #0a0a0c, indistinguishable at
      // 60%, and reusing it keeps this out of the token list. The alpha matters
      // more than the hue: below the 0.7 blur threshold in conf/rules.lua, so
      // the compositor leaves the dimmed desktop sharp and only blurs the
      // toolbar and badge sitting on top of it.
      color: Theme.alpha(Theme.bg, 0.6)
    }

    MouseArea {
      id: drag
      anchors.fill: parent
      hoverEnabled: true

      property real anchorX: 0
      property real anchorY: 0
      property real lastX: 0
      property real lastY: 0

      cursorShape: win.target === "region" ? Qt.CrossCursor : Qt.ArrowCursor

      onPressed: mouse => {
        drag.anchorX = mouse.x
        drag.anchorY = mouse.y
        drag.lastX = mouse.x
        drag.lastY = mouse.y
        if (win.target === "region" && !keys.spaceHeld) {
          win.selX = mouse.x; win.selY = mouse.y
          win.selW = 0; win.selH = 0
        }
      }

      onPositionChanged: mouse => {
        if (win.target === "window") {
          if (!drag.pressed) win.snapToWindowAt(mouse.x, mouse.y)
          return
        }
        // screen / all screens own their rectangle; only region is dragged out.
        if (!drag.pressed || win.target !== "region") return

        if (keys.spaceHeld) {
          // Space moves the whole selection instead of resizing it, and the
          // anchor travels with it so releasing space resumes the drag cleanly.
          win.selX += mouse.x - drag.lastX
          win.selY += mouse.y - drag.lastY
          drag.anchorX += mouse.x - drag.lastX
          drag.anchorY += mouse.y - drag.lastY
          win.clampSelection()
        } else {
          win.selX = Math.min(drag.anchorX, mouse.x)
          win.selY = Math.min(drag.anchorY, mouse.y)
          win.selW = Math.abs(mouse.x - drag.anchorX)
          win.selH = Math.abs(mouse.y - drag.anchorY)
        }
        drag.lastX = mouse.x
        drag.lastY = mouse.y
      }

      // Every target except region already knows its rectangle before the click
      // -- the hovered window, this screen, all screens -- so the click that
      // picks it is also the click that takes it. Region is the one target where
      // a click is the start of a drag rather than a decision.
      onClicked: if (win.target !== "region") win.arm()
    }

    Item {   // selection: rect, handles, size badge
      id: selection
      x: win.selX
      y: win.selY
      width: win.selW
      height: win.selH
      visible: win.hasSelection && win.target !== "all"

      Rectangle {
        anchors.fill: parent
        radius: 4                       // drawn geometry, like the bar's glyphs
        color: Theme.alpha(Theme.accent, 0.04)
        border.width: 1.5
        border.color: Theme.accent
      }

      Repeater {   // 7px corner handles
        model: [[0, 0], [1, 0], [0, 1], [1, 1]]
        Rectangle {
          required property var modelData
          x: modelData[0] * selection.width - 3.5
          y: modelData[1] * selection.height - 3.5
          width: 7; height: 7; radius: 2
          color: Theme.text
          border.width: 1.5
          border.color: Theme.accent
        }
      }

      Rectangle {   // "1680 × 920"
        anchors { right: parent.right; bottom: parent.top; bottomMargin: 8 }
        width: dims.implicitWidth + 16
        height: dims.implicitHeight + 6
        radius: Theme.radiusPip
        color: Theme.alpha(Theme.glassBase, 0.85)
        border.width: 1
        border.color: Theme.hairlineStrong

        Text {
          id: dims
          anchors.centerIn: parent
          // Logical pixels, the unit grim -g takes. The written PNG is this
          // multiplied by the monitor scale.
          text: `${Math.round(win.selW)} × ${Math.round(win.selH)}`
          font { family: Theme.fontMono; pixelSize: 10; weight: 600 }
          color: Theme.text
        }
      }
    }

    Text {   // hint, top left
      anchors { top: parent.top; left: parent.left; topMargin: 14; leftMargin: 20 }
      text: win.notice !== "" ? win.notice
        : win.target === "window" ? "hover a window · ↵ captures · esc cancels"
        : "drag to select · space moves selection · esc cancels"
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: win.notice !== "" ? Theme.accentSoft : Theme.text3
    }

    CaptureToolbar {
      anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
      overlay: win
    }
  }
}
