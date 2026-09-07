pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme

// The pixelate tool's rectangles, drawn on the frozen frame.
//
// Real mosaic, not a stand-in pattern: each rectangle shows the still itself
// loaded at one pixel per block and drawn back up unsmoothed, which is the same
// thing scripts/c7shell-crop.py burns into the PNG. A hatch or a solid fill
// would be quicker and would also be a lie -- you would be agreeing to a
// redaction without having seen whether it actually covers the thing.
//
// Every rectangle here is in the overlay's LOGICAL pixels. The caller scales
// them by the frame's device ratio on the way to the cropper, exactly as it
// does with the crop.
Item {
  id: mosaic

  // The frozen frame's url, and the mosaic's grid in logical pixels.
  required property url source
  required property real block

  property var rects: []
  // The one being dragged out. Drawn with the others so the mosaic appears
  // under the pointer rather than after the release.
  property rect live: Qt.rect(0, 0, 0, 0)
  property bool drawing: false

  // Where the drag started, and how far it has actually travelled. The travel
  // is measured before snapping, or a click that moved nothing would still
  // snap out to a full block and leave a stray square on the shot.
  property real anchorX: 0
  property real anchorY: 0
  property real rawW: 0
  property real rawH: 0

  // Outward to the block grid, so a rectangle covers whole blocks. Half a
  // block of the thing being hidden, left legible along an edge, is the one
  // failure a redaction cannot have -- and it keeps this preview and the
  // cropper's own snapping agreed on where the grid falls.
  function snap(x, y, w, h) {
    const x0 = Math.floor(x / mosaic.block) * mosaic.block
    const y0 = Math.floor(y / mosaic.block) * mosaic.block
    const x1 = Math.ceil((x + w) / mosaic.block) * mosaic.block
    const y1 = Math.ceil((y + h) / mosaic.block) * mosaic.block
    return Qt.rect(x0, y0, x1 - x0, y1 - y0)
  }

  function begin(x, y) {
    mosaic.anchorX = x
    mosaic.anchorY = y
    mosaic.rawW = 0
    mosaic.rawH = 0
    mosaic.live = mosaic.snap(x, y, 0, 0)
    mosaic.drawing = true
  }

  function extend(x, y) {
    if (!mosaic.drawing) return
    mosaic.rawW = Math.abs(x - mosaic.anchorX)
    mosaic.rawH = Math.abs(y - mosaic.anchorY)
    mosaic.live = mosaic.snap(Math.min(mosaic.anchorX, x), Math.min(mosaic.anchorY, y),
                              mosaic.rawW, mosaic.rawH)
  }

  // Same 2px floor as the crop selection: below it the drag was a click.
  function commit() {
    if (!mosaic.drawing) return
    // Rebuilt from its numbers, not appended as it stands. A `rect` read off a
    // property is a reference to that property in Qt 6, so pushing `live`
    // itself put an alias of the live rectangle into the list: every committed
    // redaction then followed the next drag, and the frame ended up with one
    // mosaic on it however many were drawn.
    if (mosaic.rawW >= 2 && mosaic.rawH >= 2)
      mosaic.rects = mosaic.rects.concat([Qt.rect(mosaic.live.x, mosaic.live.y,
                                                  mosaic.live.width,
                                                  mosaic.live.height)])
    mosaic.drawing = false
    mosaic.live = Qt.rect(0, 0, 0, 0)
  }

  function undo() {
    if (mosaic.drawing || mosaic.rects.length === 0) return
    mosaic.rects = mosaic.rects.slice(0, -1)
  }

  function clear() {
    mosaic.rects = []
    mosaic.drawing = false
    mosaic.live = Qt.rect(0, 0, 0, 0)
  }

  Repeater {
    model: mosaic.drawing ? mosaic.rects.concat([mosaic.live]) : mosaic.rects

    delegate: Item {
      id: patch
      required property rect modelData

      x: patch.modelData.x
      y: patch.modelData.y
      width: patch.modelData.width
      height: patch.modelData.height
      clip: true

      Image {
        // The whole frame, offset so the piece showing through the clip is the
        // piece this rectangle covers. One downscale shared by every
        // rectangle, since they all ask for the same sourceSize.
        x: -patch.modelData.x
        y: -patch.modelData.y
        width: mosaic.width
        height: mosaic.height
        source: mosaic.source
        sourceSize: Qt.size(Math.max(1, Math.round(mosaic.width / mosaic.block)),
                            Math.max(1, Math.round(mosaic.height / mosaic.block)))
        // One pixel per block, drawn back up with nearest neighbour: flat
        // squares. Smoothing here would blur the mosaic back into a shape you
        // can still read.
        fillMode: Image.Stretch
        smooth: false
      }

      Rectangle {   // so an all-grey block is still visibly a redaction
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.5)
      }
    }
  }
}
