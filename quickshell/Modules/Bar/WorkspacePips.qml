import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import qs.Theme
import "Pips.js" as Pips

// Dice-face workspace tiles: the pip layout IS the workspace number.
// 1–6 = die faces, 7–12 = dominos, 13+ = numeral. Shows only THIS monitor's
// workspaces, at most 5 tiles — the window slides to keep focus visible.
// focused = crimson + glow, urgent = accent fill + border, others = raised.
Row {
  id: root
  spacing: 6

  // This bar's own Hyprland monitor. Focus is per-monitor: reading the global
  // Hyprland.focusedWorkspace lights the same pip on every monitor's bar.
  required property var monitor

  readonly property int tile: 20

  // Ids that survive the ≤5 window. A rebuilt plain-int array is safe here —
  // the Repeater model stays the ObjectModel itself (Repeater rule); this
  // array is only consulted by delegates for `visible`. id > 0 skips
  // Hyprland's special (scratchpad) workspaces, which have negative ids.
  readonly property var visibleIds: {
    const ids = Hyprland.workspaces.values
      .filter(w => w.id > 0 && w.monitor?.name === root.monitor?.name)
      .map(w => w.id)
      .sort((a, b) => a - b)
    return Pips.window(ids, root.monitor?.activeWorkspace?.id ?? -1, 5)
  }

  Repeater {
    model: Hyprland.workspaces   // ObjectModel bound directly: Repeater rule

    Rectangle {
      id: pip
      required property var modelData
      readonly property int wsId: pip.modelData.id
      readonly property var face: Pips.layout(pip.wsId)
      readonly property bool focused: root.monitor?.activeWorkspace?.id === pip.wsId
      // Display precedence focused > urgent: a workspace you are looking at
      // has nothing left to demand attention about.
      readonly property bool urgent: !pip.focused && (pip.modelData.urgent ?? false)
      readonly property color dotColor: pip.focused ? Theme.text
        : pip.urgent ? Theme.alpha(Theme.text, 0.8)
        : Theme.alpha(Theme.text, 0.55)

      visible: root.visibleIds.indexOf(pip.wsId) !== -1
      width: root.tile; height: root.tile
      radius: Theme.radiusPip
      color: focused ? Theme.accent
        : urgent ? Theme.accentFill
        : Theme.surface07
      border.width: urgent ? 1 : 0
      border.color: Theme.accentBorder

      Repeater {
        model: pip.face.dots

        Rectangle {
          required property var modelData
          x: modelData[0] * root.tile - pip.face.dotSize / 2
          y: modelData[1] * root.tile - pip.face.dotSize / 2
          width: pip.face.dotSize; height: pip.face.dotSize
          radius: pip.face.dotSize / 2
          color: pip.dotColor
        }
      }

      // Domino mid divider (7–12)
      Rectangle {
        visible: pip.face.divider
        x: 4; width: root.tile - 8; height: 1
        y: root.tile / 2 - 0.5
        color: Theme.alpha(Theme.text, 0.25)
      }

      // 13+ fallback: the number itself
      Text {
        visible: pip.face.numeral
        anchors.centerIn: parent
        text: pip.wsId
        color: pip.dotColor
        font.family: Theme.fontMono
        font.pixelSize: 9
        font.weight: 700
      }

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
