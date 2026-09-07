import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Theme
import qs.Services

// Mockup 9a. The capture opens here instead of going straight to the
// clipboard: the shot centred on a dimmed desktop, what it is top-left, what
// to do with it top-right, and the tools along the bottom.
//
// A layer surface rather than a toplevel, for the same reason the capture
// overlay is one -- there is no window to manage, nothing to tile it against,
// and the thing being edited is a picture of the desktop it is covering.
PanelWindow {
  id: win

  // Latched, not bound, exactly as CaptureOverlay latches it: Hyprland's
  // focused monitor follows the cursor, and an editor that migrates to the
  // other output mid-drag takes the canvas geometry with it. It tracks
  // normally while the editor is down, so the value is already right at the
  // instant it opens.
  property var mon: Hyprland.focusedMonitor

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() {
      if (!AnnotateService.editing) win.mon = Hyprland.focusedMonitor
    }
  }

  // Never null: the name match fails after a hotplug, and a null screen is a
  // window that cannot map while everything else believes the editor is open.
  screen: Quickshell.screens.find(s => s.name === win.mon?.name)
    ?? Quickshell.screens[0]
    ?? null

  anchors { top: true; left: true; right: true; bottom: true }
  // A zero exclusive zone still respects the bar's reservation, which would
  // leave the editor short of the screen by the topbar margin.
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.namespace: "c7shell-annotate"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  visible: AnnotateService.editing

  // The four swatches resolved out of the palette, for the renderer. The
  // service holds tokens because nothing under Services/ can see Theme; this
  // is the one place both are in scope, and it re-resolves if the accent
  // changes under a live editor.
  Binding {
    target: AnnotateService
    property: "palette"
    value: ({
      accent: String(Theme.accent),
      text: String(Theme.text),
      bg: String(Theme.bg),
      warning: String(Theme.warning)
    })
  }

  // Esc with edits on screen asks once rather than throwing them away. Armed
  // by the first press, disarmed by anything else -- a confirmation you can
  // walk away from by carrying on working.
  property bool confirmingDiscard: false

  onVisibleChanged: {
    if (!win.visible) {
      win.mon = Hyprland.focusedMonitor
      return
    }
    win.confirmingDiscard = false
    keys.forceActiveFocus()
  }

  readonly property string hint: {
    if (win.confirmingDiscard)
      return "esc again abandons the edits · anything else carries on"
    if (AnnotateService.tool === "crop") return "drag the part to keep · esc returns to select"
    if (AnnotateService.tool === "rect") return "drag out a rectangle · esc returns to select"
    return "click to select · drag to move · del removes · ↵ copies"
  }

  // Esc means the same thing at two depths: leave the tool, then leave the
  // editor. Anything drawn is asked about once on the way out.
  function escape() {
    if (AnnotateService.tool !== "select") {
      AnnotateService.tool = "select"
      return
    }
    if (AnnotateService.edited && !win.confirmingDiscard) {
      win.confirmingDiscard = true
      return
    }
    AnnotateService.abandon()
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true

    Keys.onPressed: event => {
      // Any key that is not a second esc takes the confirmation back down, so
      // the prompt cannot sit armed behind a minute of drawing and then catch
      // the next esc.
      if (event.key !== Qt.Key_Escape) win.confirmingDiscard = false

      switch (event.key) {
      case Qt.Key_Escape:
        win.escape(); event.accepted = true; return
      case Qt.Key_Return:
      case Qt.Key_Enter:
        AnnotateService.apply(); event.accepted = true; return
      case Qt.Key_Delete:
      case Qt.Key_Backspace:
        AnnotateService.remove(AnnotateService.selected); event.accepted = true; return
      case Qt.Key_Z:
        if (!(event.modifiers & Qt.ControlModifier)) break
        if (event.modifiers & Qt.ShiftModifier) AnnotateService.redo()
        else AnnotateService.undo()
        event.accepted = true; return
      case Qt.Key_Y:
        if (!(event.modifiers & Qt.ControlModifier)) break
        AnnotateService.redo(); event.accepted = true; return
      }

      // Tools bind to 1-9 in bar order. The bar owns that order, so it owns
      // the mapping too -- a tool added to it becomes reachable by number
      // without this file learning about it.
      const slot = event.key - Qt.Key_1
      if (slot >= 0 && slot < toolbar.tools.length) {
        AnnotateService.tool = toolbar.tools[slot].id
        event.accepted = true
      }
    }

    Rectangle {   // the desktop, backed off behind the shot
      anchors.fill: parent
      color: Theme.bg
    }

    AnnotationCanvas {
      id: canvas
      anchors {
        top: parent.top; left: parent.left; right: parent.right
        bottom: bars.top
        topMargin: 56; leftMargin: 56; rightMargin: 56; bottomMargin: 24
      }
    }

    EditorTopBar {
      anchors {
        top: parent.top; left: parent.left; right: parent.right
        topMargin: 14; leftMargin: 20; rightMargin: 20
      }
    }

    Column {
      id: bars
      anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
      spacing: 8

      Text {   // what the active tool is waiting for, above its own options
        anchors.horizontalCenter: parent.horizontalCenter
        text: win.hint
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: win.confirmingDiscard ? Theme.accentSoft : Theme.text3
      }

      OptionStrip { anchors.horizontalCenter: parent.horizontalCenter }
      EditorToolBar { id: toolbar; anchors.horizontalCenter: parent.horizontalCenter }
    }
  }
}
