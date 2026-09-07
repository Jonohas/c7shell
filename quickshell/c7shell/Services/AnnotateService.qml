pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The annotation scene, and everything about it that has to outlive the
// editor's surface: the file being edited, the objects on it, the undo
// history, and the render that turns the two into a PNG.
//
// The surface is a layer shell window and is unmapped whenever the editor is
// down, which takes its properties with it. The scene cannot live there for
// the same reason the capture countdown cannot live on the capture overlay.
//
// COORDINATES ARE IMAGE PIXELS. Every object is stored in pixels of the source
// PNG, never in the surface's logical pixels. The canvas draws the shot
// scaled to fit between the tool bars, so a view coordinate means nothing
// without the scale it was measured at -- and a scale factor applied in two
// places is a scale factor that will disagree with itself. It is applied when
// drawing, and nowhere else.
Singleton {
  id: root

  readonly property string renderer:
    Qt.resolvedUrl("../scripts/c7shell-render.py").toString().replace(/^file:\/\//, "")

  // -- what is being edited ----------------------------------------------
  // Non-empty exactly while the editor is up. It carries the path, because
  // the surface has to draw the file.
  property string source: ""
  readonly property url sourceUrl: root.source === "" ? "" : `file://${root.source}`
  readonly property bool editing: root.source !== ""
  // The capture's own "copy" chip, carried across: the editor is a different
  // surface from the toolbar that chose it, and ↵ here is what finally acts
  // on the answer.
  property bool copyOnDone: true

  // The source's own size, in its own pixels. Set by the canvas once the
  // image has loaded -- nothing else in the shell knows it, and reading it off
  // the monitor would be the display scale rather than the file's.
  property int imageWidth: 0
  property int imageHeight: 0

  // -- the scene ----------------------------------------------------------
  // Plain JS objects in a plain array, reassigned rather than mutated: a
  // `property var` only notifies on assignment, so an in-place push updates
  // nothing on screen.
  property var objects: []
  // Index into `objects`, or -1. Selection is scene state rather than surface
  // state because undo restores it: undoing a delete with nothing selected
  // afterwards leaves you looking for what came back.
  property int selected: -1
  // {x, y, w, h} in image pixels, or null for the whole frame.
  property var cropBox: null

  readonly property bool edited: root.objects.length > 0 || root.cropBox !== null

  // The frame as it stands, which is what the top-left reports and what a
  // newly drawn object is clamped to.
  readonly property int frameWidth: root.cropBox ? root.cropBox.w : root.imageWidth
  readonly property int frameHeight: root.cropBox ? root.cropBox.h : root.imageHeight

  // -- tools --------------------------------------------------------------
  // select | rect | crop for now; the rest of the bar arrives with its issue.
  property string tool: "select"

  // The four swatches, as palette TOKENS rather than colours. Nothing under
  // Services/ imports qs.Theme, and a literal here would be a copy of
  // palette.json that drifts from it -- an annotation drawn in last year's
  // crimson on a shell wearing this year's. The editor fills `palette` in
  // below and the token is resolved once, on the way to the renderer.
  readonly property var swatches: ["accent", "text", "bg", "warning"]
  // token -> "#rrggbb", handed over by the editor, which can see Theme.
  property var palette: ({})

  // Per-tool options, sticky across captures the way a pen keeps its colour.
  // In memory only: this is the same shell process, and a preference that
  // survives a reboot is a store rather than a service.
  property var options: ({
    rect: { colour: "accent", stroke: 3, fill: false, radius: 4 }
  })

  function setOption(tool, key, value) {
    const next = JSON.parse(JSON.stringify(root.options))
    next[tool][key] = value
    root.options = next
    // A restyle applies to whatever is selected, which is what makes the
    // option strip a property sheet rather than only a default for the next
    // thing drawn.
    if (root.selected >= 0 && root.objects[root.selected].kind === tool)
      root.patch(root.selected, { [key]: value })
  }

  // -- opening and closing -------------------------------------------------
  signal opened()

  function begin(path, copy) {
    root.source = path
    root.copyOnDone = copy
    root.objects = []
    root.selected = -1
    root.cropBox = null
    root.imageWidth = 0
    root.imageHeight = 0
    root.undoStack = []
    root.redoStack = []
    root.tool = "select"
    root.opened()
  }

  // Leaves the editor without exporting. The capture itself is NOT thrown
  // away: grim already wrote it, and a screenshot you took is not something to
  // delete because you decided not to draw on it. It goes to the toast like
  // any other capture, minus the clipboard, so it can still be opened, shown
  // in the folder or binned from there.
  function abandon() {
    const shot = root.source
    root.source = ""
    if (shot !== "") CaptureService.deliver(shot, false)
  }

  // -- history -------------------------------------------------------------
  // Snapshots, not inverse operations. Undo has to cover place, move, resize,
  // restyle and delete, and every one of those is "the scene, before" -- a
  // scene is tens of small objects, so the cheap version of this is also the
  // correct one.
  property var undoStack: []
  property var redoStack: []
  readonly property bool canUndo: root.undoStack.length > 0
  readonly property bool canRedo: root.redoStack.length > 0

  function snapshot() {
    return { objects: JSON.parse(JSON.stringify(root.objects)),
             cropBox: root.cropBox ? JSON.parse(JSON.stringify(root.cropBox)) : null,
             selected: root.selected }
  }

  function restore(s) {
    root.objects = s.objects
    root.cropBox = s.cropBox
    root.selected = s.selected
  }

  // Called BEFORE a mutation, by whatever is about to make it. A drag calls it
  // once when the drag starts rather than on every mouse move, or undo would
  // walk back across a hundred intermediate positions.
  function commit() {
    root.undoStack = root.undoStack.concat([root.snapshot()])
    // Any new edit ends the redo branch: keeping it would offer to redo
    // something that no longer follows from what is on screen.
    root.redoStack = []
  }

  function undo() {
    if (!root.canUndo) return
    const prev = root.undoStack[root.undoStack.length - 1]
    root.redoStack = root.redoStack.concat([root.snapshot()])
    root.undoStack = root.undoStack.slice(0, -1)
    root.restore(prev)
  }

  function redo() {
    if (!root.canRedo) return
    const next = root.redoStack[root.redoStack.length - 1]
    root.undoStack = root.undoStack.concat([root.snapshot()])
    root.redoStack = root.redoStack.slice(0, -1)
    root.restore(next)
  }

  // -- editing the scene ---------------------------------------------------
  function add(obj) {
    root.commit()
    root.objects = root.objects.concat([obj])
    root.selected = root.objects.length - 1
  }

  // Merge fields into one object. Takes a copy of the whole list: a `rect` or
  // an object read out of a `property var` and edited in place is a reference
  // to what is already there, so the change lands without a notification and
  // the snapshot taken afterwards is of the new state, not the old.
  function patch(i, fields) {
    if (i < 0 || i >= root.objects.length) return
    const next = root.objects.slice()
    next[i] = Object.assign({}, next[i], fields)
    root.objects = next
  }

  function remove(i) {
    if (i < 0 || i >= root.objects.length) return
    root.commit()
    root.objects = root.objects.slice(0, i).concat(root.objects.slice(i + 1))
    root.selected = -1
  }

  function setCrop(box) {
    root.commit()
    root.cropBox = box
    root.selected = -1
  }

  // -- export --------------------------------------------------------------
  // The scene goes to the renderer as one argv string rather than through a
  // temporary file. A file would need writing, waiting for and cleaning up,
  // and the wait is the part with no honest answer -- FileView reports that it
  // wrote, not that the bytes are readable by another process.
  function scene() {
    return JSON.stringify({
      source: root.source,
      // Tokens become colours here and only here. The renderer takes hex
      // because it has no palette and no business having one.
      objects: root.objects.map(o => Object.assign({}, o, { colour: root.hex(o.colour) })),
      crop: root.cropBox
    })
  }

  // An unknown token would reach the renderer as the word itself, which it
  // rejects -- so the export fails loudly rather than drawing the annotation
  // in a colour nobody chose.
  function hex(token) { return root.palette[token] ?? token }

  // "shot-20260907-143000.png" -> "shot-20260907-143000-edited.png". Beside
  // the original rather than over it: the capture is what was on the screen
  // and the export is what you decided to show, and losing the first to the
  // second is not recoverable.
  function exportPath() {
    const dot = root.source.lastIndexOf(".")
    return dot < 0 ? `${root.source}-edited` : `${root.source.substring(0, dot)}-edited.png`
  }

  // ↵. The editor closes on the way out rather than waiting for the render:
  // the file is being written from a scene this object still holds, and the
  // surface has nothing left to do with it.
  function apply() {
    if (render.running) return
    render.pending = root.exportPath()
    render.copy = root.copyOnDone
    render.exec(["python3", root.renderer, render.pending, "--scene-json", root.scene()])
    root.source = ""
  }

  Process {
    id: render
    property string pending: ""
    property bool copy: false
    stderr: StdioCollector { id: renderErr }
    onExited: (code, status) => {
      if (code !== 0 || status !== 0) {
        // Loud, because the editor has already closed: an export that fails in
        // silence is a screenshot you annotated, pressed enter on, and cannot
        // find.
        CaptureService.fail("annotation failed",
          renderErr.text.trim() || `the renderer exited ${code}`)
        return
      }
      CaptureService.deliver(render.pending, render.copy)
    }
  }
}
