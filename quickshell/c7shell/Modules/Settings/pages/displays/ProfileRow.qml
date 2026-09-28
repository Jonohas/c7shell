pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common

// One selectable profile line: name + a note, and a chip that reads "active"
// for the current pick or "use" to switch to it. Greyed and unclickable when
// its screens are not all connected.
Item {
  id: prow

  property string profName
  property string sub: ""
  property bool available: true
  property bool current: false
  // { "<desc>": { position, mode, scale } }, straight out of displays-state.json.
  property var displays: ({})
  signal use()

  width: parent.width
  implicitHeight: 30
  opacity: prow.available || prow.current ? 1 : 0.45

  Column {
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
    spacing: 1

    Text {
      text: prow.profName
      font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
      color: Theme.text
    }
    Text {
      visible: prow.sub !== ""
      text: prow.sub
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.45)
    }
  }

  HoverHandler { id: prowHover }

  // The shape of the arrangement, on hover: enough to tell "laptop left of
  // ultrawide" from "laptop under it" without switching to the profile.
  ProfilePreview {
    anchors { right: useChip.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
    width: 76
    height: 22
    displays: prow.displays
    visible: prowHover.hovered
  }

  Chip {
    id: useChip

    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    text: prow.current ? "active" : "use"
    accented: prow.current
    enabled: prow.available && !prow.current
    onTriggered: prow.use()
  }

  // A profile's saved arrangement as boxes, in the same logical coordinate
  // space ArrangeCanvas draws the live desk in: position is the logical
  // top-left, mode over scale is the logical size. Draws nothing for a profile
  // with no positions -- "auto" has none.
  component ProfilePreview: Item {
    id: prev

    property var displays: ({})

    readonly property var rects: {
      const out = []
      for (const d of Object.values(prev.displays ?? ({}))) {
        const p = /^(-?\d+)x(-?\d+)$/.exec(d.position ?? "")
        if (!p) continue
        const m = /^(\d+)x(\d+)/.exec(d.mode ?? "")
        const s = d.scale > 0 ? d.scale : 1
        out.push({
          x: parseInt(p[1]), y: parseInt(p[2]),
          // A profile may leave the mode to hyprland; 1920x1080 keeps such a
          // screen a plausible box instead of a zero-size one.
          w: (m ? parseInt(m[1]) : 1920) / s,
          h: (m ? parseInt(m[2]) : 1080) / s
        })
      }
      return out
    }

    // Fit the bounding box into this item, centred. Same k-scaling as
    // ArrangeCanvas, without the drag half.
    readonly property var plan: {
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
      for (const r of prev.rects) {
        x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y)
        x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h)
      }
      if (!isFinite(x0)) return { k: 0, x0: 0, y0: 0, ox: 0, oy: 0 }
      const w = Math.max(1, x1 - x0), h = Math.max(1, y1 - y0)
      const k = Math.min(prev.width / w, prev.height / h)
      return {
        k: k, x0: x0, y0: y0,
        ox: (prev.width - w * k) / 2,
        oy: (prev.height - h * k) / 2
      }
    }

    Repeater {
      model: prev.rects

      Rectangle {
        required property var modelData

        x: prev.plan.ox + (modelData.x - prev.plan.x0) * prev.plan.k
        y: prev.plan.oy + (modelData.y - prev.plan.y0) * prev.plan.k
        // Minus a pixel so butted-up screens read as two boxes, not one.
        width: Math.max(2, modelData.w * prev.plan.k - 1)
        height: Math.max(2, modelData.h * prev.plan.k - 1)
        radius: 2
        color: Theme.alpha(Theme.text, 0.12)
        border { width: 1; color: Theme.alpha(Theme.text, 0.35) }
      }
    }
  }
}
