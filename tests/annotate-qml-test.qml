import QtQuick
import qs.Services

// Self-check for the annotate editor's scene (run by tests/test-annotate.sh).
//
// The surface itself is a layer shell window and needs a compositor, so what
// is reachable here is the part that decides what the exported PNG contains:
// the object list, the history, the crop, and the JSON the renderer is handed.
// That is also the part whose failures are silent -- an annotation that does
// not survive into the scene is one you watched yourself draw and then did not
// get, and the file still lands in ~/Pictures looking finished.
Window {
  id: root
  visible: true
  width: 240; height: 120

  function step(fn) {
    try {
      fn()
    } catch (e) {
      console.log("ANNOTATE-TEST-FAIL: " + e.message)
      Qt.exit(1)
    }
  }

  function check(cond, msg) {
    if (!cond) throw new Error(msg)
  }

  // The scene the renderer is handed, which is the only thing that decides
  // what the saved PNG contains. Every object here is one the editor drew on
  // screen: an object that does not survive into the scene is an annotation
  // you watched yourself make and then did not get.
  function scene() {
    AnnotateService.begin("/tmp/c7shell-test-shot.png", true)
    root.check(AnnotateService.editing, "begin() did not open the editor")
    root.check(String(AnnotateService.sourceUrl) === "file:///tmp/c7shell-test-shot.png",
      `the canvas would be handed "${AnnotateService.sourceUrl}" to draw`)
    root.check(!AnnotateService.edited, "a freshly opened capture already counted as edited")

    AnnotateService.palette = { accent: "#ffffff" }
    AnnotateService.add({ kind: "rect", x: 10.4, y: 20, w: 30, h: 40,
                          colour: "accent", stroke: 3, fill: false, radius: 4 })
    root.check(AnnotateService.edited, "a rectangle on the shot did not count as an edit")
    root.check(AnnotateService.selected === 0, "a newly drawn object was not selected")

    const s = JSON.parse(AnnotateService.scene())
    root.check(s.source === "/tmp/c7shell-test-shot.png",
      `the renderer would be pointed at ${s.source}`)
    root.check(s.objects.length === 1, `${s.objects.length} objects reached the renderer, not 1`)
    // The token is resolved on the way out and nowhere else: the renderer has
    // no palette, and a scene carrying the word "accent" draws nothing.
    root.check(s.objects[0].colour === "#ffffff",
      `the renderer was handed the colour ${s.objects[0].colour} instead of a hex value`)
    root.check(s.objects[0].kind === "rect" && s.objects[0].w === 30,
      "the object reached the renderer with its geometry changed")
    root.check(s.crop === null, "an uncropped capture still told the renderer to crop")
  }

  // Undo covers every operation, because it is the scene before rather than an
  // inverse of any one of them. A move that undo cannot walk back is a
  // misplaced arrow you can only fix by taking the screenshot again.
  function history() {
    root.check(AnnotateService.canUndo, "placing a rectangle left nothing to undo")
    root.check(!AnnotateService.canRedo, "there was something to redo before anything was undone")

    AnnotateService.commit()
    AnnotateService.patch(0, { x: 200 })
    root.check(AnnotateService.objects[0].x === 200, "the move did not land")
    AnnotateService.undo()
    root.check(AnnotateService.objects[0].x === 10.4,
      `undoing the move left it at ${AnnotateService.objects[0].x}`)
    AnnotateService.redo()
    root.check(AnnotateService.objects[0].x === 200,
      `redoing the move left it at ${AnnotateService.objects[0].x}`)

    // A snapshot taken by reference would follow the object it was meant to
    // remember, and undo would then restore the state it was already in.
    // Written in place on purpose: patch() copies, so a shallow snapshot
    // survives every mutation the editor actually makes and the invariant
    // would go untested until the first caller that does not copy.
    AnnotateService.undo()
    AnnotateService.commit()
    AnnotateService.objects[0].x = 500
    AnnotateService.undo()
    root.check(AnnotateService.objects[0].x === 10.4,
      `the history is holding references, not copies: x came back as ${AnnotateService.objects[0].x}`)

    // Editing after an undo ends the redo branch: offering to redo something
    // that no longer follows from what is on screen is worse than not offering.
    AnnotateService.commit()
    root.check(!AnnotateService.canRedo, "a new edit left the old redo branch in place")

    AnnotateService.remove(0)
    root.check(AnnotateService.objects.length === 0, "delete did not remove the object")
    root.check(AnnotateService.selected === -1, "a deleted object was left selected")
    AnnotateService.undo()
    root.check(AnnotateService.objects.length === 1, "undo did not bring the deleted object back")
  }

  // The crop is a field on the scene, not a new file: nothing is cut until the
  // export, so undo has the rest of the shot to give back.
  function cropping() {
    AnnotateService.imageWidth = 1000
    AnnotateService.imageHeight = 800
    root.check(AnnotateService.frameWidth === 1000,
      `an uncropped frame reported ${AnnotateService.frameWidth} wide`)

    AnnotateService.setCrop({ x: 100, y: 50, w: 400, h: 300 })
    root.check(AnnotateService.frameWidth === 400 && AnnotateService.frameHeight === 300,
      "the top-left readout would still show the uncropped size")
    root.check(JSON.parse(AnnotateService.scene()).crop.x === 100,
      "the crop did not reach the renderer")
    AnnotateService.undo()
    root.check(AnnotateService.cropBox === null, "undo did not give the cropped-away part back")

    // Beside the original, never over it: the capture is what was on the
    // screen and the export is what you decided to show.
    AnnotateService.source = "/tmp/shots/shot-1.png"
    root.check(AnnotateService.exportPath() === "/tmp/shots/shot-1-edited.png",
      `the export would be written to ${AnnotateService.exportPath()}`)
  }

  Component.onCompleted: root.step(() => {
    root.scene()
    root.history()
    root.cropping()
    console.log("ANNOTATE-TEST-PASS")
    Qt.exit(0)
  })
}
