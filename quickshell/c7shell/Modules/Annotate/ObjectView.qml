import QtQuick
import qs.Theme
import qs.Services

// One annotation on the canvas: what it looks like, and -- in select mode --
// the ring and the eight handles that make it a live object rather than paint.
//
// It reads its object out of the scene and writes changes back through
// AnnotateService rather than holding any of its own. A drag that edited local
// state and pushed it at the end would be a second copy of the object for the
// length of the drag, and undo would have nothing to walk back to.
Item {
  id: view

  required property int index
  required property var object
  // The canvas, for the one scale factor. Passed rather than looked up so
  // this has no opinion about where it is mounted.
  required property var canvas

  readonly property bool selected: AnnotateService.selected === view.index
  readonly property bool selectable: AnnotateService.tool === "select"

  // A rectangle dragged right-to-left arrives with a negative width. It is
  // normalised for display and for the handles, and left alone in the scene:
  // the renderer normalises too, and a drag that rewrote its own origin
  // half-way through would jump under the pointer.
  readonly property real nx: view.object.w < 0 ? view.object.x + view.object.w : view.object.x
  readonly property real ny: view.object.h < 0 ? view.object.y + view.object.h : view.object.y
  readonly property real nw: Math.abs(view.object.w)
  readonly property real nh: Math.abs(view.object.h)

  x: view.canvas.toViewX(view.nx)
  y: view.canvas.toViewY(view.ny)
  width: view.nw * view.canvas.viewScale
  height: view.nh * view.canvas.viewScale

  // -- the annotation itself ----------------------------------------------
  Rectangle {
    anchors.fill: parent
    visible: view.object.kind === "rect"
    radius: view.object.radius * view.canvas.viewScale
    color: view.object.fill ? Theme.swatch(view.object.colour) : "transparent"
    // The stroke is in image pixels like everything else, so it thins with the
    // shot as the shot is scaled down -- which is what the exported file will
    // show, and the point of previewing at all.
    border.width: view.object.fill ? 0 : Math.max(1, view.object.stroke * view.canvas.viewScale)
    border.color: Theme.swatch(view.object.colour)
  }

  // -- selection ------------------------------------------------------------
  Rectangle {
    anchors.fill: parent
    anchors.margins: -3
    visible: view.selected && view.selectable
    color: "transparent"
    radius: 3
    border.width: 1
    border.color: Theme.accentSoft
  }

  MouseArea {
    id: body
    anchors.fill: parent
    enabled: view.selectable
    cursorShape: Qt.SizeAllCursor

    property real grabX: 0
    property real grabY: 0

    onPressed: mouse => {
      AnnotateService.selected = view.index
      // Once per drag, not once per move: undo has to walk back to where the
      // object was before it was picked up, not through every position it
      // passed through on the way.
      AnnotateService.commit()
      body.grabX = mouse.x
      body.grabY = mouse.y
    }

    onPositionChanged: mouse => {
      if (!body.pressed) return
      const dx = (mouse.x - body.grabX) / view.canvas.viewScale
      const dy = (mouse.y - body.grabY) / view.canvas.viewScale
      AnnotateService.patch(view.index,
        { x: view.object.x + dx, y: view.object.y + dy })
    }
  }

  // Eight handles: the four corners move two edges, the four sides move one.
  // Each is described by which edges it owns, so the resize is one function
  // rather than eight.
  Repeater {
    model: view.selected && view.selectable ? view.handles : []

    Rectangle {
      required property var modelData

      width: 9
      height: 9
      radius: 2
      x: view.width * modelData.ax - width / 2
      y: view.height * modelData.ay - height / 2
      color: Theme.accent
      border.width: 1
      border.color: Theme.textOnAccent

      MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: modelData.cursor

        property real grabX: 0
        property real grabY: 0

        onPressed: mouse => {
          AnnotateService.commit()
          grabX = mouse.x
          grabY = mouse.y
        }

        onPositionChanged: mouse => {
          if (!pressed) return
          view.resize(modelData,
            (mouse.x - grabX) / view.canvas.viewScale,
            (mouse.y - grabY) / view.canvas.viewScale)
        }
      }
    }
  }

  // ax/ay are the handle's position as a fraction of the box; dx/dy say which
  // edges it drags. Written out rather than computed so the cursors can be
  // read off the same table.
  readonly property var handles: [
    { ax: 0,   ay: 0,   dx: -1, dy: -1, cursor: Qt.SizeFDiagCursor },
    { ax: 0.5, ay: 0,   dx: 0,  dy: -1, cursor: Qt.SizeVerCursor },
    { ax: 1,   ay: 0,   dx: 1,  dy: -1, cursor: Qt.SizeBDiagCursor },
    { ax: 1,   ay: 0.5, dx: 1,  dy: 0,  cursor: Qt.SizeHorCursor },
    { ax: 1,   ay: 1,   dx: 1,  dy: 1,  cursor: Qt.SizeFDiagCursor },
    { ax: 0.5, ay: 1,   dx: 0,  dy: 1,  cursor: Qt.SizeVerCursor },
    { ax: 0,   ay: 1,   dx: -1, dy: 1,  cursor: Qt.SizeBDiagCursor },
    { ax: 0,   ay: 0.5, dx: -1, dy: 0,  cursor: Qt.SizeHorCursor }
  ]

  // Dragging a left or top handle moves the origin as well as the size, which
  // is the whole difference between the two directions.
  function resize(handle, dx, dy) {
    const o = view.object
    const fields = {}
    if (handle.dx < 0) { fields.x = o.x + dx; fields.w = o.w - dx }
    else if (handle.dx > 0) fields.w = o.w + dx
    if (handle.dy < 0) { fields.y = o.y + dy; fields.h = o.h - dy }
    else if (handle.dy > 0) fields.h = o.h + dy
    AnnotateService.patch(view.index, fields)
  }
}
