import QtQuick
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings

// The bar's own modules, as choices rather than as look-and-feel. Everything
// here writes ShellStore (~/.config/hypr/shell.json); the page owns no state.
SettingsPage {
  id: root

  title: "Topbar"
  subtitle: "what the bar shows"

  SettingsCard {
    width: parent.width
    spacing: 8

    ToggleRow {
      width: parent.width
      label: "global menu"
      checked: ShellStore.globalMenu
      onToggled: ShellStore.values.globalMenu = !ShellStore.globalMenu
    }

    // Not a decoration: turning this off gives the menus BACK to the app, and
    // an app that is already open keeps whatever it decided when its window was
    // created (Qt asks for the registrar once and caches the answer). Say so,
    // or the toggle looks broken on the dolphin window that prompted it.
    Text {
      width: parent.width
      text: ShellStore.globalMenu
        ? "the focused app's menu bar, next to the workspaces. apps that export "
          + "one (dolphin, other Qt/KDE apps) hide their own while this is on."
        : "apps draw their own menu bars. windows already open keep the menu "
          + "bar they started with — reopen them to see the change."
      wrapMode: Text.WordWrap
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.35)
    }
  }
}
