import QtQuick
import QtQuick.Effects
import qs.Theme
import qs.Services

// The shot and everything drawn on it. Owns the one scale factor in the
// editor: the capture is displayed at whatever fraction of itself fits
// between the bars, and every coordinate crossing between the surface and the
// scene goes through toImage / toView here.
//
// It is never upscaled. A 400px shot blown up to fill a 4K screen is a blurry
// picture of a sharp file, and the annotations would be placed against the
// blur.
Item {
  id: board

  // The frame as it stands -- the crop, if there is one, and otherwise the
  // whole image.
  readonly property int frameW: AnnotateService.frameWidth
  readonly property int frameH: AnnotateService.frameHeight
  readonly property int originX: AnnotateService.cropBox ? AnnotateService.cropBox.x : 0
  readonly property int originY: AnnotateService.cropBox ? AnnotateService.cropBox.y : 0

  // NOT `scale`: that is Item's own transform, and assigning it here would
  // scale this object and everything under it as well as the arithmetic.
  readonly property real viewScale: board.frameW > 0 && board.frameH > 0
    ? Math.min(board.width / board.frameW, board.height / board.frameH, 1)
    : 1
  readonly property real viewW: board.frameW * board.viewScale
  readonly property real viewH: board.frameH * board.viewScale
  readonly property real shotX: (board.width - board.viewW) / 2
  readonly property real shotY: (board.height - board.viewH) / 2

  function toImageX(vx) { return (vx - board.shotX) / board.viewScale + board.originX }
  function toImageY(vy) { return (vy - board.shotY) / board.viewScale + board.originY }
  function toViewX(ix) { return (ix - board.originX) * board.viewScale + board.shotX }
  function toViewY(iy) { return (iy - board.originY) * board.viewScale + board.shotY }

  Item {
    id: frame
    x: board.shotX
    y: board.shotY
    width: board.viewW
    height: board.viewH
    // The crop is a window onto the image rather than a new file: nothing is
    // cut until the export, so undo has the rest of the shot to give back.
    clip: true

    RectangularShadow {
      anchors.fill: parent
      radius: 8
      color: Theme.panelShadowColor
      offset.y: 24
      blur: 70
      z: -1
    }

    Image {
      id: shot
      x: -board.originX * board.viewScale
      y: -board.originY * board.viewScale
      width: AnnotateService.imageWidth * board.viewScale
      height: AnnotateService.imageHeight * board.viewScale
      source: AnnotateService.sourceUrl
      // Every capture is a new file, so there is nothing to gain by keeping a
      // full-screen frame in the cache -- and a reused path would draw the
      // previous one.
      cache: false
      fillMode: Image.Stretch
      // The file's own size, which nothing else in the shell knows: the
      // monitor reports the display scale, not the pixels grim wrote. Set from
      // implicitWidth, which stays the natural size when width is bound.
      onStatusChanged: {
        if (shot.status !== Image.Ready) return
        AnnotateService.imageWidth = shot.implicitWidth
        AnnotateService.imageHeight = shot.implicitHeight
      }
    }

    Repeater {
      model: AnnotateService.objects
      // `index` is declared required on ObjectView and injected by name; the
      // scene object arrives as modelData and is handed over under the name
      // it is read by.
      ObjectView {
        required property var modelData
        object: modelData
        canvas: board
      }
    }
  }

  // -- drawing a new object, and the crop -----------------------------------
  // Under the objects, so a click that lands on one in select mode reaches
  // that object's own area first. With any other tool the object areas are
  // disabled and everything arrives here.
  MouseArea {
    id: draw
    anchors.fill: parent
    z: -1
    cursorShape: AnnotateService.tool === "select" ? Qt.ArrowCursor : Qt.CrossCursor

    // The drag in progress, in image pixels. Not in the scene yet: a click
    // that never became a drag should not leave a zero-sized object behind,
    // and the crop is not applied until it is let go of.
    property real ax: 0
    property real ay: 0
    property real bx: 0
    property real by: 0
    property bool drawing: false

    readonly property real rx: Math.min(draw.ax, draw.bx)
    readonly property real ry: Math.min(draw.ay, draw.by)
    readonly property real rw: Math.abs(draw.bx - draw.ax)
    readonly property real rh: Math.abs(draw.by - draw.ay)

    onPressed: mouse => {
      if (AnnotateService.tool === "select") {
        // Empty canvas, in select mode: a click on nothing is how you let go
        // of what is selected.
        AnnotateService.selected = -1
        return
      }
      draw.ax = board.toImageX(mouse.x)
      draw.ay = board.toImageY(mouse.y)
      draw.bx = draw.ax
      draw.by = draw.ay
      draw.drawing = true
    }

    onPositionChanged: mouse => {
      if (!draw.drawing) return
      draw.bx = board.toImageX(mouse.x)
      draw.by = board.toImageY(mouse.y)
    }

    onReleased: {
      if (!draw.drawing) return
      draw.drawing = false
      // A click is not a rectangle. Without a floor, every stray click on the
      // canvas leaves an invisible object in the scene that undo has to be
      // spent on.
      if (draw.rw < 2 || draw.rh < 2) return
      if (AnnotateService.tool === "crop") {
        AnnotateService.setCrop({ x: Math.round(draw.rx), y: Math.round(draw.ry),
                                  w: Math.round(draw.rw), h: Math.round(draw.rh) })
        // Crop is the one tool with nothing left to do afterwards.
        AnnotateService.tool = "select"
        return
      }
      AnnotateService.add(Object.assign(
        { kind: AnnotateService.tool, x: draw.rx, y: draw.ry, w: draw.rw, h: draw.rh },
        AnnotateService.options[AnnotateService.tool]))
    }
  }

  // What the drag is going to produce, drawn where it is going to land.
  Rectangle {
    visible: draw.drawing
    x: board.toViewX(draw.rx)
    y: board.toViewY(draw.ry)
    width: draw.rw * board.viewScale
    height: draw.rh * board.viewScale
    color: "transparent"
    border.width: 1
    border.color: Theme.accentSoft
  }
}
