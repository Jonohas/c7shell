//@ pragma UseQApplication
// Scratch harness for looking at one component without running the whole shell.
//
//   tools/qml-preview qs.Common/BatteryGlyph --zoom 8
//   tools/qml-preview qs.Modules.Settings/SettingsWindow --show appearance
//
// Launched by tools/qml-preview, which sets QS_PREVIEW and regenerates the
// registry first; running this file directly previews whatever QS_PREVIEW says.
//
// One entry point, not a preview-*.qml per component. Two constraints shape it.
//
// It has to sit at the config root: `qs` is not a real module, it is whatever
// directory quickshell registers under the file `-p` points at, so from a
// subdirectory every `qs.*` import resolves against that subdirectory and fails.
//
// And the target cannot be a path or a string import. Quickshell generates the
// qmldir for a directory only if the entry file statically references something
// in it, so a Loader pointed at Common/BatteryGlyph.qml gets a directory that
// was never scanned -- the component loads but its own sibling `Icon` does not
// resolve, and Qt.createQmlObject("import qs.Common; ...") fails outright.
// tools/qml-preview generates PreviewRegistry.qml to hold those references.
import Quickshell
import QtQuick
import qs.Theme

Scope {
  id: root

  readonly property string target: Quickshell.env("QS_PREVIEW") ?? ""

  // Bar glyphs are ~20px; at 1:1 there is nothing to look at.
  readonly property real zoom: Number(Quickshell.env("QS_PREVIEW_ZOOM") ?? 1) || 1

  // Windows that open themselves need a nudge -- SettingsWindow builds nothing
  // until show() runs. Passed through as that call's argument.
  readonly property string showArg: Quickshell.env("QS_PREVIEW_SHOW") ?? ""

  PreviewRegistry { id: registry }

  Component.onCompleted: root.build()

  function build() {
    const component = registry.components[root.target]
    if (component === undefined) {
      console.error(`preview: unknown target ${JSON.stringify(root.target)}. `
        + `tools/qml-preview --list shows what is available.`)
      return Qt.quit()
    }

    // Built under `root` rather than under the stage, because the stage cannot
    // be torn down again: a Scope that owns its own window would be destroyed
    // with it. Visual components log one "not placed in the graphics scene"
    // warning for the tick before adopt() reparents them -- expected, not a
    // fault, and the cost of not knowing which kind this is until it exists.
    const obj = component.createObject(root)
    if (obj === null) {
      console.error(`preview: ${root.target} failed to build\n${component.errorString()}`)
      return Qt.quit()
    }

    // `anchors` is the tell for a visual Item. A Scope that owns its own window
    // -- SettingsWindow, the popovers -- has none, and is already a top level:
    // reparenting it into a stage would give it a second window around its own.
    // `anchors` is the tell for a visual Item. A Scope that owns its own window
    // -- SettingsWindow, the popovers -- has none and is already a top level:
    // the stage would wrap a second window around its own.
    if (obj.anchors !== undefined) stage.adopt(obj)
    if (root.showArg !== "" && typeof obj.show === "function") obj.show(root.showArg)
  }

  // Only built for components that need somewhere to be drawn.
  Loader {
    id: stage
    active: false

    function adopt(item) {
      stage.active = true
      item.parent = stage.item.holder
    }

    sourceComponent: FloatingWindow {
      // The window tracks the component, so a 20px glyph and a 700px panel both
      // come up at their own proportions rather than a guessed default.
      implicitWidth: Math.max(160, holder.width * root.zoom + 64)
      implicitHeight: Math.max(120, holder.height * root.zoom + 64)
      title: `preview: ${root.target}`
      // The Loader hands back the window; adopt() needs the frame inside it.
      property alias holder: holder
      color: Theme.bg

      Item {
        id: holder
        anchors.centerIn: parent
        scale: root.zoom
        width: childrenRect.width
        height: childrenRect.height
      }
    }
  }
}
