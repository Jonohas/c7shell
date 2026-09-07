import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import qs.Theme
import qs.Common
import qs.Services
import "../../Common/Pips.js" as Pips

// Dice-face workspace tiles: the pip layout IS the workspace number.
// 1–6 = die faces, 7–12 = dominos, 13+ = numeral. Shows only THIS monitor's
// workspaces, at most 10 tiles — the window slides to keep focus visible.
// focused = crimson + glow, urgent = accent fill + border, others = raised.
Row {
  id: root
  spacing: 6

  // This bar's own Hyprland monitor. Focus is per-monitor: reading the global
  // Hyprland.focusedWorkspace lights the same pip on every monitor's bar.
  required property var monitor

  readonly property int tile: 20

  // The special (scratchpad) workspace this bar's monitor owns, or null. Shown
  // as a trailing tile so it can be toggled and so you can see when you are on
  // it -- the numeric pips deliberately skip it (id > 0 above).
  readonly property var specialWs: Hyprland.workspaces.values
    .find(w => w.name === "special:magic" && w.monitor?.name === root.monitor?.name) ?? null

  // Whether special:magic is currently open on this monitor. Hyprland never
  // marks the special workspace `active`/`focused` and never makes it the
  // monitor's activeWorkspace (it is an overlay), so the only live signal is
  // the activespecialv2 event: "<id>,<name>,<monitor>" on open, ",,<monitor>"
  // on close. lastIpcObject seeds the initial value but never refreshes.
  property bool specialActive: root.monitor?.lastIpcObject?.specialWorkspace?.name === "special:magic"

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "activespecialv2")
        return
      const parts = event.data.split(",")
      if (parts[parts.length - 1] !== root.monitor?.name)
        return
      root.specialActive = parts[1] === "special:magic"
    }
  }

  // Ids that survive the ≤10 window. A rebuilt plain-int array is safe here —
  // the Repeater model stays the ObjectModel itself (Repeater rule); this
  // array is only consulted by delegates for `visible`. id > 0 skips
  // Hyprland's special (scratchpad) workspaces, which have negative ids.
  readonly property var visibleIds: {
    const ids = Hyprland.workspaces.values
      .filter(w => w.id > 0 && w.monitor?.name === root.monitor?.name)
      .map(w => w.id)
      .sort((a, b) => a - b)
    return Pips.window(ids, root.monitor?.activeWorkspace?.id ?? -1, 10)
  }

  Repeater {
    model: Hyprland.workspaces   // ObjectModel bound directly: Repeater rule

    DiceTile {
      id: pip
      required property var modelData
      readonly property int wsId: pip.modelData.id
      readonly property bool focused: root.monitor?.activeWorkspace?.id === pip.wsId
      // Display precedence focused > urgent: a workspace you are looking at
      // has nothing left to demand attention about.
      readonly property bool urgent: !pip.focused && (pip.modelData.urgent ?? false)

      value: pip.wsId
      tile: root.tile
      mode: ShellStore.workspaceIndicator
      // Hyprland reports an unnamed workspace's name as its own number as a
      // string; that is not a name, and the tile should fall back to the
      // numeral rather than print it twice as wide.
      label: pip.modelData.name === `${pip.wsId}` ? "" : (pip.modelData.name ?? "")
      dotColor: pip.focused ? Theme.text
        : pip.urgent ? Theme.alpha(Theme.text, 0.8)
        : Theme.alpha(Theme.text, 0.55)

      visible: root.visibleIds.indexOf(pip.wsId) !== -1
      color: pip.focused ? Theme.accent
        : pip.urgent ? Theme.accentFill
        : Theme.surface07
      border.width: pip.urgent ? 1 : 0
      border.color: Theme.accentBorder

      RectangularShadow {   // focus glow, spec `0 0 10px rgba(229,58,68,.5)`
        visible: pip.focused
        anchors.fill: parent
        radius: pip.radius
        color: Theme.accentGlow
        offset: Qt.vector2d(0, 0)
        blur: 10
        z: -1
      }

      MouseArea {
        anchors.fill: parent
        // This Hyprland build parses dispatches as Lua: the stock `workspace N`
        // string is a syntax error here, so use the config's own dispatcher
        // (conf/binds.lua binds workspace keys the same way).
        onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${pip.wsId} })`)
      }
    }
  }

  // Special (scratchpad) tile. Same look as a focused numeric tile when the
  // scratchpad is open, dimmed when it is hidden. Click toggles it, matching
  // Super+S (conf/binds.lua: hl.dsp.workspace.toggle_special("magic")).
  DiceTile {
    id: special
    visible: root.specialWs !== null
    glyph: "S"
    value: 0
    tile: root.tile
    dotColor: root.specialActive ? Theme.text : Theme.alpha(Theme.text, 0.55)
    color: root.specialActive ? Theme.accent : Theme.surface07

    RectangularShadow {   // focus glow, spec `0 0 10px rgba(229,58,68,.5)`
      visible: root.specialActive
      anchors.fill: parent
      radius: special.radius
      color: Theme.accentGlow
      offset: Qt.vector2d(0, 0)
      blur: 10
      z: -1
    }

    MouseArea {
      anchors.fill: parent
      onClicked: Hyprland.dispatch(`hl.dsp.workspace.toggle_special("magic")`)
    }
  }
}
