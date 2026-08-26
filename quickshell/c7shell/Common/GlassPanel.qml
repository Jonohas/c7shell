import QtQuick
import qs.Theme

// Glass surface: near-black translucent fill + 1px hairline. Actual blur is
// done by Hyprland (layerrule on the quickshell namespace), not in QML.
Rectangle {
  property real glassAlpha: Theme.glassAlphaPanel

  radius: Theme.radiusPanel
  color: Theme.alpha(Theme.glassBase, glassAlpha)
  border.width: 1
  border.color: Theme.hairline
}
