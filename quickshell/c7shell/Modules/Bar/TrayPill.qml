import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.Theme

Rectangle {
  id: pillBg
  implicitWidth: root.implicitWidth + 20   // content tuning, not a token
  implicitHeight: Theme.pillHeight
  radius: Theme.pillRadius
  color: Theme.surface05

  // Collapse entirely when nothing is DRAWN, so the bar loses its gap too -
  // counting registered items would leave an empty 8px hole when the only
  // things registered are hidden ones.
  visible: SystemTray.items.values.some(i => !root.hiddenItems.includes(i.id))

  Row {
    id: root
    anchors.centerIn: parent

    spacing: 0

    // Tray ids that are registered but deliberately not drawn. Solaar only ever
    // reported the mouse battery, which is not worth a permanent slot.
    readonly property var hiddenItems: ["indicator-solaar"]

    visible: true

    // Whichever entry the cursor is over, or null. Drives the shared tooltip.
    property var hovered: null

    // Hyprland has no minimize, and it ignores the wlr set_minimized request, so a
    // hidden special workspace is the stand-in: the window is genuinely off every
    // visible workspace rather than shoved off the edge of one.
    readonly property string toolboxClass: "jetbrains-toolbox"
    readonly property string minimizedWorkspace: "special:minimized"
    readonly property int toolboxWidth: 430  // Toolbox's window is a fixed 430x670

    // workspace is a live binding here. lastIpcObject is not - it never refreshes
    // after a move - so it is only safe to match on class, which cannot change.
    readonly property var toolboxWindow: Hyprland.toplevels.values
      .find(t => t.lastIpcObject?.class === root.toolboxClass) ?? null

    // Tray ids are not window classes - "discord_status_icon_1" has to reach
    // class "discord", "spotify-client" reach "spotify", "toolbox" reach
    // "jetbrains-toolbox". Nothing in the SNI spec links an item to its window,
    // so match on tokens shared between the item's names and a window class.
    readonly property var idNoise: ["status", "icon", "indicator", "client", "app", "tray", "applet"]

    function windowFor(item) {
      const tokens = [item.id, item.title, item.tooltipTitle]
        .filter(Boolean).join(" ").toLowerCase()
        .split(/[^a-z0-9]+/)
        .filter(t => t.length > 2 && !root.idNoise.includes(t))

      return Hyprland.toplevels.values.find(toplevel => {
        const cls = (toplevel.lastIpcObject?.class ?? "").toLowerCase()
        return cls !== "" && tokens.some(t => cls.includes(t) || t.includes(cls))
      }) ?? null
    }

    Repeater {
      model: SystemTray.items

      MouseArea {
        id: entry
        required property var modelData

        // Hidden per-delegate rather than by filtering the model: handing Repeater
        // a new array is what segfaulted WorkspaceWidget. Row skips invisible
        // items and their spacing, so the slot closes up on its own.
        visible: !root.hiddenItems.includes(entry.modelData.id)

        implicitWidth: 22
        implicitHeight: 22
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onEntered: root.hovered = entry
        onExited: if (root.hovered === entry) root.hovered = null

        // Right click (or a menu-only item) hands off to the app's own DBus menu,
        // which display() renders as a native popup - no menu building here.
        onClicked: click => {
          if (click.button === Qt.RightButton || entry.modelData.onlyMenu) {
            // display() places the menu in the PARENT WINDOW's coordinates, so the
            // anchor point has to be mapped out of the entry first - passing entry
            // coordinates drops every menu in the bar's top-left corner.
            const at = entry.mapToItem(null, entry.width / 2, entry.height)
            entry.modelData.display(entry.QsWindow.window, at.x, at.y)
          } else if (click.button === Qt.MiddleButton) {
            entry.modelData.secondaryActivate()
          } else if (entry.modelData.id === "toolbox") {
            entry.toggleToolbox()
          } else {
            // Navigate to the app's window - focuswindow follows it onto whatever
            // workspace it lives on. activate() is only the fallback: it is what
            // the app itself does with a click, which on Wayland is often nothing
            // at all (Toolbox ignores it entirely), and it cannot switch workspace.
            const window = root.windowFor(entry.modelData)
            if (window) Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${window.address}" })`)
            else entry.modelData.activate()
          }
        }

        function toggleToolbox() {
          const window = root.toolboxWindow
          if (!window) return

          if (window.workspace?.name === root.minimizedWorkspace) entry.restoreToolbox()
          else entry.dispatchToolbox(`workspace = "${root.minimizedWorkspace}", silent = true`)
        }

        function restoreToolbox() {
          const screen = entry.QsWindow.window.screen
          const centre = screen.x + entry.mapToItem(null, entry.width / 2, 0).x
          // Clamp so a 430px window tucked under a right-hand icon stays on screen.
          const x = Math.round(Math.max(screen.x + 8,
            Math.min(screen.x + screen.width - root.toolboxWidth - 8,
              centre - root.toolboxWidth / 2)))

          // Onto the workspace being looked at, then under the icon, then focused.
          // Toolbox re-places itself at x=-440 whenever the tray host restarts, so
          // restore always repositions rather than trusting where it currently is.
          const workspace = Hyprland.focusedWorkspace
          if (workspace) entry.dispatchToolbox(`workspace = "${workspace.name}", silent = true`)
          entry.dispatchToolbox(`x = ${x}, y = ${screen.y + 32}, exact = true`)
          Hyprland.dispatch(`hl.dsp.focus({ window = "class:${root.toolboxClass}" })`)
        }

        function dispatchToolbox(args) {
          Hyprland.dispatch(`hl.dsp.window.move({ ${args}, window = "class:${root.toolboxClass}" })`)
        }

        onWheel: wheel => entry.modelData.scroll(wheel.angleDelta.y, false)

        Rectangle {
          anchors.fill: parent
          radius: 6
          color: entry.containsMouse ? Theme.surface07 : "transparent"
        }

        // App icons are already coloured, so unlike the Chip glyphs they are not tinted.
        Image {
          anchors.centerIn: parent
          width: 14
          height: 14
          // Hidden entries never render, but Image would still fetch their themed
          // icon and warn when the theme lacks it (solaar's battery-060).
          source: entry.visible ? entry.modelData.icon : ""
          sourceSize: Qt.size(28, 28)  // 2x, downscaled so it stays crisp
        }
      }
    }

    // One tooltip window reused across icons - it just re-anchors to the hovered one.
    PopupWindow {
      id: tip

      visible: root.hovered !== null
      grabFocus: false
      color: "transparent"
      implicitWidth: label.implicitWidth + 12
      implicitHeight: label.implicitHeight + 8

      anchor {
        item: root.hovered
        edges: Edges.Bottom
        gravity: Edges.Bottom
      }

      Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: Theme.alpha(Theme.glassBase, Theme.glassAlphaPanel)
        border.width: 1
        border.color: Theme.hairline

        Text {
          id: label
          anchors.centerIn: parent
          color: Theme.text2
          font { family: Theme.fontMono; pixelSize: 10 }
          text: {
            const item = root.hovered?.modelData
            return item ? (item.tooltipTitle || item.title || item.id) : ""
          }
        }
      }
    }
  }
}
