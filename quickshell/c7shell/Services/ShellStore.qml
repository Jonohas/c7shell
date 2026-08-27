pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Shell preferences: the parts of the shell that are a choice rather than a
// look-and-feel value. AppearanceStore owns appearance.json because hyprland's
// lua reads it back; nothing outside the shell reads this file, so it only has
// to be somewhere stable and hand-editable. ~/.config/hypr is that place --
// c7shell-setup guarantees the directory exists, and appearance.json and
// displays.json are already in it. FileView cannot create a missing parent
// directory, so a fresh ~/.config/c7shell would silently never persist.
Singleton {
  id: root

  // Settings pages assign straight to this — writes persist themselves.
  readonly property alias values: adapter

  // False until the file has been read (or found missing). Consumers that push
  // a preference somewhere else -- the appmenu daemon -- wait for it, so the
  // adapter's defaults are never mistaken for the user's answer.
  property bool ready: false

  // Whether the focused app's menu bar is shown in the top bar. Off does more
  // than hide the chips: AppMenuService tells the daemon to drop
  // com.canonical.AppMenu.Registrar, so apps keep drawing their own menu bar
  // instead of exporting it to a shell that would not render it.
  readonly property bool globalMenu: root.values.globalMenu

  FileView {
    id: file

    path: `${Quickshell.env("HOME")}/.config/hypr/shell.json`
    watchChanges: true
    // First run has no file; that is expected, not something to warn about.
    printErrors: false

    onFileChanged: file.reload()
    onAdapterUpdated: file.writeAdapter()
    onLoaded: root.ready = true
    // Write the defaults out so the file exists to be hand-edited.
    onLoadFailed: err => {
      if (err !== FileViewError.FileNotFound) return
      root.ready = true
      file.writeAdapter()
    }

    JsonAdapter {
      id: adapter

      property bool globalMenu: true
    }
  }
}
