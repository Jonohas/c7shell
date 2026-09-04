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

  // -- the still, once a delayed capture's shutter has already gone --------
  // The delay exists to capture what is only on screen while the pointer is
  // on it, so its rectangle cannot be drawn beforehand: see CaptureService's
  // note. While this is up the surface is showing a picture of the screen,
  // not the screen, and ↵ cuts the rectangle out of that picture.
  readonly property bool frozen: CaptureService.frozen !== ""
  // The still is the output's own pixels, so its native width over this
  // surface's logical width is exactly the ratio grim worked in. Measured
  // rather than read off the monitor: one scale factor, from the file that
  // actually has to be cut.
  readonly property real deviceRatio: still.implicitWidth > 0 && win.width > 0
    ? still.implicitWidth / win.width
    : 1

  // What the hint line says instead of its usual text, for a beat.
  property string notice: ""
  Timer { id: noticeLife; interval: 1600; onTriggered: win.notice = "" }

  // Top left. A notice wins for a beat; otherwise this says what the stage the
  // capture is actually at is waiting for.
  readonly property string hint: {
    if (win.notice !== "") return win.notice
    const pick = win.target === "window" ? "hover a window" : "drag to select"
    if (win.frozen) return `frozen frame · ${pick} · ↵ captures · esc discards`
    if (win.target === "window") return "hover a window · ↵ captures · esc cancels"
    return "drag to select · space moves selection · esc cancels"
  }

  onVisibleChanged: {
    if (!win.visible) {
      // Re-latch on the way down: focus may have moved while the overlay held
      // `mon` frozen, and the next open must not start in that stale frame.
      win.mon = Hyprland.focusedMonitor
      // Closing on a still nobody cut throws it away. cropFrozen() claims the
      // frame first, so the capture path never reaches this.
      CaptureService.discardFrozen()
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
    // A frozen reopen is one capture continuing, so the target chosen before
    // the countdown still stands. A fresh open starts at region.
    if (!win.frozen) win.target = "region"
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
    // Second stage of a delayed capture: the surface is showing a still, so ↵
    // cuts the rectangle out of it rather than taking anything new.
    if (win.frozen) { win.cut(); return }

    // region and window do not know their rectangle yet; screen and all
    // screens do, by definition.
    const needsRectangle = win.target === "region" || win.target === "window"

    // First stage of a delayed one. Nothing is selected, on purpose: with the
    // delay on, a rectangle drawn now cannot be around the hover menu the
    // delay was turned on for. So the shutter takes the whole output and the
    // rectangle is drawn on the frame it brings back.
    if (win.delayed && win.mode === "shot") {
      win.loadShutter(needsRectangle ? "freeze" : "shoot")
      CaptureService.close()
      // A visible countdown, not a longer sleep: the pill draws the seconds
      // while the overlay is down, so you can see when to be hovering.
      CaptureService.startCountdown(win.mon?.name ?? win.screen?.name ?? "")
      return
    }

    // No rectangle means no capture. Falling through would silently grab the
    // whole default output instead, which is not what either target asked for.
    if (needsRectangle && win.nothingSelected()) return

    win.loadShutter(win.mode === "rec" ? "record" : "shoot")
    CaptureService.close()
    fire.restart()
  }

  // Says so, and reports it, rather than letting ↵ do nothing: an overlay that
  // just ignores the key is its own kind of silent failure, so the hint line
  // says which of the two things is missing.
  function nothingSelected() {
    if (win.hasSelection) return false
    win.notice = win.target === "window" ? "hover a window first" : "drag a region first"
    noticeLife.restart()
    return true
  }

  // What the shutter will do, and to what. Latched onto the timer rather than
  // read when it triggers: `mon` and the selection have both moved on by then,
  // and a delayed one waits three seconds before reading any of it.
  function loadShutter(action) {
    win.clampSelection()
    fire.action = action
    // A freeze is always the whole output -- the rectangle is the next stage's
    // business, not grim's.
    fire.geometry = action === "freeze" ? "" : win.geometryArg
    // wf-recorder records one output, so "all screens" in rec mode means the
    // focused one. Screenshots really can span every output, with no -o at all.
    fire.output = action === "freeze" || win.target === "screen"
        || (win.mode === "rec" && win.target === "all")
      ? (win.mon?.name ?? "")
      : ""
  }

  // The rectangle drawn on the still, cut out of the file. Logical pixels on
  // this surface, device pixels in the PNG: the still is the output at its
  // real resolution, which on a fractionally scaled output is not the same
  // number.
  function cut() {
    if (win.nothingSelected()) return
    win.clampSelection()
    const r = win.deviceRatio
    CaptureService.cropFrozen(win.selX * r, win.selY * r, win.selW * r, win.selH * r)
    // No recomposite grace on this one: cutting a file does not care what is
    // on the screen.
    CaptureService.close()
  }

  Connections {
    target: CaptureService

    // Zero on the pill, not the shutter: the pill is a layer surface too, so
    // it needs the same recomposite grace the overlay does before grim reads
    // the screen -- which is exactly what `fire` is.
    function onCountdownElapsed() { fire.restart() }

    // The frame is in. Back up, on the still this time.
    function onFrozenChanged() {
      if (CaptureService.frozen !== "") CaptureService.open()
    }
  }

  Timer {
    id: fire
    // Every capture waits this out, delayed or not: the overlay -- and the
    // countdown pill after it -- has to be unmapped and the frame
    // recomposited before grim reads the screen.
    interval: 150

    property string geometry: ""
    property string output: ""
    // shoot | record | freeze -- freeze being the delayed capture's first
    // half, which takes the whole output so the rectangle can be drawn on it.
    property string action: "shoot"

    onTriggered: {
      if (fire.action === "record") {
        RecordingService.start({
          geometry: fire.geometry,
          output: fire.output,
          mic: win.mic,
          sysAudio: win.sysAudio,
          fps60: win.fps60
        })
      } else if (fire.action === "freeze") {
        CaptureService.freeze(fire.output, win.copyToClipboard)
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

    Image {   // the frozen frame, under the dim
      id: still
      anchors.fill: parent
      visible: win.frozen
      source: CaptureService.frozenUrl
      // The output's own pixels drawn back onto the output at 1:1, so no
      // aspect juggling -- and no smoothing, which would be a lie about what
      // was on the screen at the shutter.
      fillMode: Image.Stretch
      smooth: false
      // The URL is new for every capture (CaptureService says why), so there
      // is nothing to gain by keeping the last full-screen frame in the cache.
      cache: false
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
      text: win.hint
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: win.notice !== "" ? Theme.accentSoft : Theme.text3
    }

    CaptureToolbar {
      anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
      overlay: win
    }
  }
}
