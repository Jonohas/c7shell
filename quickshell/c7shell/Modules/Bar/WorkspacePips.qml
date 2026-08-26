import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import qs.Theme
import qs.Common
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
}
