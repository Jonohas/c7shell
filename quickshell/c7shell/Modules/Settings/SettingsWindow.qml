pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Theme
import qs.Services
import qs.Modules.Settings.pages

// 2a/2b: the 790px settings window. Sidebar on the left, one page on the right.
//
// Quickshell's FloatingWindow exposes no decoration or class property (checked
// against quickshell-window.qmltypes: title, minimumSize, maximumSize,
// minimized, maximized, fullscreen, parentWindow and nothing else), so the
// "no close/min/max buttons" of the mock is a compositor concern — Hyprland
// draws no server-side titlebar, and QT_WAYLAND_DISABLE_WINDOWDECORATION=1
// keeps Qt from drawing its own. Both are in INTEGRATION.md.
//
// There is no close button by design: the window is dismissed with hyprland's
// kill bind, which destroys the toplevel. Showing it again re-creates it --
// literally. The window is built by a Loader, because killing the toplevel
// destroys the underlying window and assigning `visible = true` to the corpse
// does nothing: the settings app used to open exactly once per shell process,
// and every request after the first was silently ignored.
Scope {
  id: root

  // The page outlives the window, so reopening lands where you left off and
  // show("wifi") still means something while no window exists yet.
  // `page` is a sidebar key: wifi / bluetooth / audio / appearance / …
  property string page: "appearance"

  function show(page) {
    if (page !== undefined && page !== "") root.page = page
    frame.active = true
  }

  // Popover footers route here — "network settings →" and friends.
  Connections {
    target: SettingsService
    function onOpenRequested(page) { root.show(page) }
  }

  IpcHandler {
    target: "settings"
    function open(page: string): void { root.show(page) }
  }

  Loader {
    id: frame
    active: false
    sourceComponent: windowComponent
  }

  Component {
    id: windowComponent

    FloatingWindow {
    id: win

    visible: true
    // The compositor clears this when the window is killed; drop the Loader so
    // the next show() builds a fresh window rather than reviving a dead one.
    onVisibleChanged: if (!win.visible) frame.active = false
    title: "c7shell settings"
    color: Theme.canvas
    implicitWidth: 790
    implicitHeight: 560
    // The sidebar alone is 212px; below this the pages stop making sense.
    minimumSize: Qt.size(660, 420)

    Sidebar {
      id: sidebar
      anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
      current: root.page
      onCurrentChanged: root.page = sidebar.current
    }

    Loader {
      anchors {
        left: sidebar.right; right: parent.right
        top: parent.top; bottom: parent.bottom
        leftMargin: 22; rightMargin: 22; topMargin: 18; bottomMargin: 18
      }

      // Components rather than file paths: a typo is a load error here instead
      // of a blank pane at runtime. Phase-2 entries fall through to a stub so
      // no visible nav item is a dead click.
      sourceComponent: {
        switch (sidebar.current) {
        case "appearance": return appearancePage
        case "wifi": return wifiPage
        case "bluetooth": return bluetoothPage
        case "audio": return audioPage
        case "displays": return displaysPage
        case "topbar": return topbarPage
        case "system": return systemPage
        case "power": return powerPage
        }
        return soonPage
      }
    }

    Component { id: appearancePage; AppearancePage {} }
    Component { id: wifiPage; WifiPage {} }
    Component { id: bluetoothPage; BluetoothPage {} }
    Component { id: audioPage; AudioPage {} }
    Component { id: displaysPage; DisplaysPage {} }
    Component { id: topbarPage; TopbarPage {} }
    Component { id: systemPage; SystemPage {} }
    Component { id: powerPage; PowerPage {} }

    Component {
      id: soonPage
      SettingsPage {
        title: sidebar.labelFor(sidebar.current)
        subtitle: "coming in settings phase 2"
      }
    }
  }
}
  }
