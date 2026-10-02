pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.Theme
import qs.Services
import "Arrange.js" as Arrange

// A top-down plan of the desk: one draggable tile per connected monitor, laid
// out in Hyprland's own coordinate space and staged on drop.
//
// Hyprland positions monitors in LOGICAL pixels — a 2880x1920 panel at scale 2
// occupies 1440x960 of the coordinate space — so every rectangle here is
// width/scale by height/scale, and the plan re-fits itself when a scale slider
// moves. Reading m.x/m.y/m.width/m.height/m.scale inside plan() is what makes
// the whole layout a live binding: QML captures those property reads even
// through the loop.
Item {
  id: root

  // A screen staged off is on its way out: it takes no part in the plan, and
  // the others may move into the space it leaves.
  readonly property var mons: Hyprland.monitors.values
    .filter(m => DisplayService.stagedFor(m.name).disabled !== true)

  // Off by default: the tiles read as a plan, not a fiddle-able thing, until the
  // "rearrange" button on DisplaysPage arms them.
  property bool dragEnabled: false

  // A monitor's effective logical top-left: the staged position if one is
  // pending, else the live one. plan(), target() and the tiles all read through
  // this, so a staged move shows across the whole plan before it is applied.
  function staged(m) {
    return /^(-?\d+)x(-?\d+)$/.exec(DisplayService.stagedFor(m.name).position ?? "")
  }
  function ex(m) { const r = root.staged(m); return r ? parseInt(r[1]) : m.x }
  function ey(m) { const r = root.staged(m); return r ? parseInt(r[2]) : m.y }

  // A monitor's effective logical SIZE. Hyprland reports width/height as the
  // panel's own mode, untransformed: a 2560x1440 screen rotated 90 degrees
  // still reads 2560x1440 while occupying 1440x2560 of the coordinate space.
  // The odd transforms (1/3, and the flipped 5/7) swap the axes; the even ones
  // do not. Staged rotation counts, so the plan reorients before apply, same as
  // a staged move. So do a staged mode and scale: arranging against the live
  // size left a gap or an overlap the moment the new scale applied.
  function et(m) {
    return DisplayService.stagedFor(m.name).transform
      ?? (m.lastIpcObject?.transform ?? 0)
  }
  function size(m) {
    const s = DisplayService.stagedFor(m.name)
    const r = /^(\d+)x(\d+)@/.exec(s.mode ?? "")
    const w = r ? parseInt(r[1]) : m.width, h = r ? parseInt(r[2]) : m.height
    const k = s.scale ?? m.scale
    return root.et(m) % 2 === 1 ? { w: h / k, h: w / k } : { w: w / k, h: h / k }
  }
  function lw(m) { return root.size(m).w }
  function lh(m) { return root.size(m).h }

  // Fit the bounding box of every monitor into the canvas with a margin, and
  // centre it. `k` is canvas px per logical px; everything else converts
  // through it. While rearranging, half the largest screen of room goes on
  // every side, so there is somewhere to drag a screen to above, below or past
  // the end of the desk.
  readonly property var plan: {
    const pad = 14
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity, big = 0
    for (const m of root.mons) {
      x0 = Math.min(x0, root.ex(m)); y0 = Math.min(y0, root.ey(m))
      x1 = Math.max(x1, root.ex(m) + root.lw(m))
      y1 = Math.max(y1, root.ey(m) + root.lh(m))
      big = Math.max(big, root.lw(m), root.lh(m))
    }
    if (!isFinite(x0)) return { k: 1, x0: 0, y0: 0, ox: 0, oy: 0 }
    if (root.dragEnabled) {
      x0 -= big / 2; y0 -= big / 2; x1 += big / 2; y1 += big / 2
    }
    const w = Math.max(1, x1 - x0), h = Math.max(1, y1 - y0)
    const k = Math.min((root.width - pad * 2) / w, (root.height - pad * 2) / h)
    return {
      k: k, x0: x0, y0: y0,
      ox: (root.width - w * k) / 2,
      oy: (root.height - h * k) / 2
    }
  }

  function px(lx) { return root.plan.ox + (lx - root.plan.x0) * root.plan.k }
  function py(ly) { return root.plan.oy + (ly - root.plan.y0) * root.plan.k }

  // Where `me` lands if let go at logical (lx, ly), per the snap toggle and
  // reach in ShellStore, or null when the drop would be refused. The reach and
  // the flush-pull threshold are fixed in CANVAS px and divided by k, so they
  // stay the same distance under the cursor whatever the desk is scaled to.
  function target(me, lx, ly) {
    const others = root.mons.filter(o => o !== me).map(o => ({
      x: root.ex(o), y: root.ey(o), w: root.lw(o), h: root.lh(o)
    }))
    return Arrange.land({ w: root.lw(me), h: root.lh(me) }, others, lx, ly,
      12 / root.plan.k, ShellStore.arrangeSnapReach / root.plan.k,
      ShellStore.arrangeSnap)
  }

  // Stage `me` at `p`, then shift the whole desk back to 0,0. Every position
  // that changes is staged; one that does not is left alone, so a click
  // without a move stages nothing.
  function drop(me, p) {
    const desk = Arrange.normalise(root.mons.map(m => m === me
      ? { m: m, x: p.x, y: p.y }
      : { m: m, x: root.ex(m), y: root.ey(m) }))
    for (const r of desk) {
      if (r.x !== root.ex(r.m) || r.y !== root.ey(r.m))
        DisplayService.stage(r.m.name, { position: `${r.x}x${r.y}` })
    }
  }

  // The landing spot of the screen being dragged, {x, y, w, h} in logical px,
  // or null when nothing is being dragged or the drop would be refused. The
  // ghost below draws it, and release stages exactly it.
  property var ghost: null

  implicitHeight: root.dragEnabled ? 240 : 176

  // Drawn before the tiles so the dragged tile passes over it.
  Rectangle {
    visible: root.ghost !== null
    x: root.ghost ? root.px(root.ghost.x) : 0
    y: root.ghost ? root.py(root.ghost.y) : 0
    width: root.ghost ? root.ghost.w * root.plan.k : 0
    height: root.ghost ? root.ghost.h * root.plan.k : 0
    radius: Theme.radiusChip
    color: Theme.accentFillSoft
    border.width: 1
    border.color: Theme.accentBorder
  }

  // Alignment lines between the ghost and the screens it lines up with. Edge
  // lines solid, centre lines fainter, so the two read apart at a glance.
  Repeater {
    model: root.ghost ? Arrange.guides(root.ghost, root.mons
      .filter(m => m !== root.ghost.m)
      .map(m => ({ x: root.ex(m), y: root.ey(m), w: root.lw(m), h: root.lh(m) }))) : []

    Rectangle {
      required property var modelData

      x: modelData.vertical ? Math.round(root.px(modelData.at)) : root.px(modelData.from)
      y: modelData.vertical ? root.py(modelData.from) : Math.round(root.py(modelData.at))
      width: modelData.vertical ? 1 : (modelData.to - modelData.from) * root.plan.k
      height: modelData.vertical ? (modelData.to - modelData.from) * root.plan.k : 1
      color: Theme.alpha(Theme.accent, modelData.centre ? 0.45 : 0.9)
    }
  }

  Repeater {
    // The ObjectModel itself, per the repeater rule in CONVENTIONS.
    model: Hyprland.monitors

    Rectangle {
      id: tile

      required property var modelData

      visible: root.mons.indexOf(tile.modelData) >= 0

      readonly property real lw: root.lw(tile.modelData)
      readonly property real lh: root.lh(tile.modelData)

      // While a drag is in flight these hold the proposed logical position; NaN
      // means "follow the effective position" -- which is the staged spot once
      // dropped, so the tile stays where it was let go without applying anything
      // until the user presses apply.
      property real dragX: NaN
      property real dragY: NaN
      readonly property real lx: isNaN(tile.dragX) ? root.ex(tile.modelData) : tile.dragX
      readonly property real ly: isNaN(tile.dragY) ? root.ey(tile.modelData) : tile.dragY

      x: root.px(tile.lx)
      y: root.py(tile.ly)
      width: tile.lw * root.plan.k
      height: tile.lh * root.plan.k
      radius: Theme.radiusChip
      color: drag.pressed ? Theme.accentFill
        : tile.modelData.focused ? Theme.accentFillSoft : Theme.surface07
      border.width: 1
      border.color: drag.pressed || tile.modelData.focused
        ? Theme.accentBorder : Theme.hairlineStrong

      Column {
        anchors.centerIn: parent
        spacing: 1

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: tile.modelData.name
          font { family: Theme.fontMono; pixelSize: 10; weight: 600 }
          color: Theme.text
        }
        // Resolution before position: it is what tells two screens apart at a
        // glance, and the exact coordinates are in the card below anyway. The
        // smaller tile only has room for one of them.
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: tile.height > 44 && implicitWidth < tile.width - 10
          text: `${Math.round(tile.lw)}×${Math.round(tile.lh)}`
          font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
          color: Theme.alpha(Theme.text, 0.45)
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: tile.height > 60 && implicitWidth < tile.width - 10
          text: `${Math.round(tile.lx)},${Math.round(tile.ly)}`
          font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
          color: Theme.alpha(Theme.text, 0.3)
        }
      }

      MouseArea {
        id: drag

        anchors.fill: parent
        enabled: root.dragEnabled
        cursorShape: Qt.OpenHandCursor

        // Grab offset in LOGICAL px. Tracking the cursor in canvas coordinates
        // rather than the tile's own means the maths does not care that the
        // tile is moving underneath it.
        property real grabX: 0
        property real grabY: 0
        // A press that never travels is a click, and stages nothing.
        property bool moved: false

        // The cursor is clamped to the canvas, so a tile cannot be flung out
        // over the cards below and dropped somewhere it cannot be seen.
        function logical(mx, my) {
          const m = drag.mapToItem(root, mx, my)
          const p = {
            x: Math.max(0, Math.min(root.width, m.x)),
            y: Math.max(0, Math.min(root.height, m.y))
          }
          return {
            x: root.plan.x0 + (p.x - root.plan.ox) / root.plan.k,
            y: root.plan.y0 + (p.y - root.plan.oy) / root.plan.k
          }
        }

        onPressed: e => {
          const l = drag.logical(e.x, e.y)
          drag.grabX = l.x - tile.lx
          drag.grabY = l.y - tile.ly
          drag.moved = false
          tile.dragX = tile.lx
          tile.dragY = tile.ly
        }

        onPositionChanged: e => {
          if (!drag.pressed) return
          const l = drag.logical(e.x, e.y)
          const x = l.x - drag.grabX, y = l.y - drag.grabY
          if (Math.hypot(x - tile.lx, y - tile.ly) * root.plan.k > 3) drag.moved = true
          tile.dragX = x
          tile.dragY = y
          const p = drag.moved ? root.target(tile.modelData, x, y) : null
          root.ghost = p && { x: p.x, y: p.y, w: tile.lw, h: tile.lh, m: tile.modelData }
        }

        onReleased: {
          // Stage, do not apply. dragX/Y back to NaN so the tile follows the
          // staged position, which is where the ghost showed it landing -- or
          // springs back to where it was when there is no ghost.
          if (drag.moved && root.ghost) root.drop(tile.modelData, root.ghost)
          root.ghost = null
          tile.dragX = NaN
          tile.dragY = NaN
        }

        // A grab stolen mid-drag must not leave the tile stuck under a cursor
        // that is no longer driving it.
        onCanceled: {
          root.ghost = null
          tile.dragX = NaN
          tile.dragY = NaN
        }
      }
    }
  }
}
