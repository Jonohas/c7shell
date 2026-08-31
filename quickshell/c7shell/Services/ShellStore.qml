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

  // -- topbar layout --
  // "islands" drops the bar surface and lets the three clusters float as their
  // own pills; "bar" is the single container the shell has always drawn. The
  // default is the latter, so an upgrade does not rearrange anyone's screen.
  readonly property string islandStyle: root.values.islandStyle
  // dice | numerals | names -- the dice faces are the shell's own idiom, but a
  // workspace that has been NAMED in hyprland.conf has something to say that a
  // pip cannot.
  readonly property string workspaceIndicator: root.values.workspaceIndicator

  // -- battery widget --
  // Percentage and wattage are independent on purpose: the number without the
  // draw and the draw without the number are both reasonable bars.
  readonly property bool batteryPercentage: root.values.batteryPercentage
  readonly property bool batteryWattage: root.values.batteryWattage
  // Decimals on the watt figure: 0 or 1. One is the default because it is what
  // keeps the pill's reserved width from changing as the draw crosses 10 W.
  readonly property int batteryWattagePrecision: root.values.batteryWattagePrecision
  readonly property bool batteryWattageOnlyOnBattery: root.values.batteryWattageOnlyOnBattery
  // Tooltip-only: the figure is far too jumpy to sit in the bar.
  readonly property bool batteryTimeRemaining: root.values.batteryTimeRemaining
  // Whole percent. Below it the widget goes crimson and fires one toast.
  readonly property int batteryWarnBelow: root.values.batteryWarnBelow

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

      property string islandStyle: "bar"
      property string workspaceIndicator: "dice"

      property bool batteryPercentage: true
      property bool batteryWattage: false
      property int batteryWattagePrecision: 1
      property bool batteryWattageOnlyOnBattery: false
      property bool batteryTimeRemaining: true
      property int batteryWarnBelow: 15
    }
  }
}
