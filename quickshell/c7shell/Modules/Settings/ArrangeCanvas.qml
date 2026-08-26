pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.Theme
import qs.Services

// A top-down plan of the desk: one draggable tile per connected monitor, laid
// out in Hyprland's own coordinate space and applied on drop.
//
// Hyprland positions monitors in LOGICAL pixels — a 2880x1920 panel at scale 2
// occupies 1440x960 of the coordinate space — so every rectangle here is
// width/scale by height/scale, and the plan re-fits itself when a scale slider
// moves. Reading m.x/m.y/m.width/m.height/m.scale inside plan() is what makes
// the whole layout a live binding: QML captures those property reads even
// through the loop.
Item {
  id: root

  readonly property var mons: Hyprland.monitors.values

  // Fit the bounding box of every monitor into the canvas with a margin, and
  // centre it. `k` is canvas px per logical px; everything else converts
  // through it.
  readonly property var plan: {
    const pad = 14
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
    for (const m of root.mons) {
      x0 = Math.min(x0, m.x); y0 = Math.min(y0, m.y)
      x1 = Math.max(x1, m.x + m.width / m.scale)
      y1 = Math.max(y1, m.y + m.height / m.scale)
    }
    if (!isFinite(x0)) return { k: 1, x0: 0, y0: 0, ox: 0, oy: 0 }
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

  // Snap the dragged monitor's logical top-left to its neighbours' edges so
  // screens butt up instead of leaving a seam. Four candidates per axis: butt
  // after, butt before, and the two flush alignments. The threshold is fixed in
  // CANVAS px and divided by k, so it stays the same distance under the cursor
  // whatever the desk is scaled to.
  function snap(me, lx, ly) {
    const lw = me.width / me.scale, lh = me.height / me.scale
    const t = 12 / root.plan.k
    let bx = lx, by = ly, dx = t, dy = t
    for (const o of root.mons) {
      if (o === me) continue
      const ow = o.width / o.scale, oh = o.height / o.scale
      for (const c of [o.x + ow, o.x - lw, o.x, o.x + ow - lw]) {
        const d = Math.abs(c - lx)
        if (d < dx) { dx = d; bx = c }
      }
      for (const c of [o.y + oh, o.y - lh, o.y, o.y + oh - lh]) {
        const d = Math.abs(c - ly)
        if (d < dy) { dy = d; by = c }
      }
    }
    // Hyprland takes negatives happily, but a fat-fingered fling should not be
    // able to park a screen a hundred thousand pixels away where no cursor can
    // reach it.
    return {
      x: Math.round(Math.max(-20000, Math.min(20000, bx))),
      y: Math.round(Math.max(-20000, Math.min(20000, by)))
    }
  }

  implicitHeight: 176

  Repeater {
    // The ObjectModel itself, per the repeater rule in CONVENTIONS.
    model: Hyprland.monitors

    Rectangle {
      id: tile

      required property var modelData

      readonly property real lw: tile.modelData.width / tile.modelData.scale
      readonly property real lh: tile.modelData.height / tile.modelData.scale

      // While a drag is in flight these hold the proposed logical position;
      // NaN means "follow the monitor". After a drop they keep the applied
      // value until `settle` fires, so the tile does not rubber-band back to
      // the old spot during the ~400ms before Hyprland is re-read — and if
      // Hyprland refuses the move it visibly springs back, same as the scale
      // slider does.
      property real dragX: NaN
      property real dragY: NaN
      readonly property real lx: isNaN(tile.dragX) ? tile.modelData.x : tile.dragX
      readonly property real ly: isNaN(tile.dragY) ? tile.modelData.y : tile.dragY

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

      Timer {
        id: settle
        interval: 700
        onTriggered: { tile.dragX = NaN; tile.dragY = NaN }
      }

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
        cursorShape: Qt.OpenHandCursor

        // Grab offset in LOGICAL px. Tracking the cursor in canvas coordinates
        // rather than the tile's own means the maths does not care that the
        // tile is moving underneath it.
        property real grabX: 0
        property real grabY: 0

        function logical(mx, my) {
          const p = drag.mapToItem(root, mx, my)
          return {
            x: root.plan.x0 + (p.x - root.plan.ox) / root.plan.k,
            y: root.plan.y0 + (p.y - root.plan.oy) / root.plan.k
          }
        }

        onPressed: e => {
          settle.stop()
          const l = drag.logical(e.x, e.y)
          drag.grabX = l.x - tile.lx
          drag.grabY = l.y - tile.ly
          tile.dragX = tile.lx
          tile.dragY = tile.ly
        }

        onPositionChanged: e => {
          if (!drag.pressed) return
          const l = drag.logical(e.x, e.y)
          tile.dragX = l.x - drag.grabX
          tile.dragY = l.y - drag.grabY
        }

        onReleased: {
          const s = root.snap(tile.modelData, tile.dragX, tile.dragY)
          tile.dragX = s.x
          tile.dragY = s.y
          DisplayService.apply(tile.modelData.name, { position: `${s.x}x${s.y}` })
          settle.restart()
        }
      }
    }
  }
}
