import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import qs.Theme
import qs.Services

// Every popup this shell drops out of the bar: a glass panel in a transparent
// window, input masked back to the panel, dismissed by a click anywhere else.
// The three copies that used to exist drifted apart, and only one of them
// carried either of the two fixes below -- the other two got away with it only
// because they do not animate their close.
//
// Owners set `open` and `anchorItem` and do their own anchor arithmetic; the
// content goes in the default property and is parented to the panel.
PopupWindow {
  id: root

  // The window stays mapped through the fade-out, so `open` -- not `visible` --
  // is what "this popup is up" means everywhere below.
  property bool open: false

  // The item the popup hangs off. The owner usually drops it the instant the
  // popup closes, but the window is still mapped for the fade: anchoring to the
  // live value would leave the closing panel with no anchor and flash it to the
  // left edge of the screen on its way out. Latch it instead.
  property Item anchorItem: null
  property Item lastAnchor: null

  // Room around the panel for its drop shadow to fade out inside the window
  // rather than being clipped square. Asymmetric on purpose where the tail
  // falls downwards.
  property int gutterX: 60
  property int gutterTop: 60
  property int gutterBottom: 60

  property int panelWidth: 320
  // Owners size their own content; a Rectangle will not do it for them.
  property real panelHeight: 0
  property int panelRadius: Theme.radiusPanel
  property real shadowOffset: 24
  property real shadowBlur: 80
  // Menus switch too fast to fade; panels look wrong without it.
  property bool fade: true

  // The anchor's own window inside the grab as well. Without it a click on
  // another bar module is an outside click: it closes this popup and is
  // swallowed, so switching popovers takes two clicks. With it Hyprland keeps
  // the keyboard on the BAR surface, which is why keySink exists -- the bar
  // forwards what it receives back into whatever holds focus in here.
  property bool grabAnchorWindow: true

  default property alias content: panel.data
  readonly property alias panel: panel
  // The bar forwards to the PANEL, never to whatever holds focus inside it: a
  // password field lives in a Repeater delegate that the next wi-fi scan
  // rebuilds, and a stale pointer to a freed delegate took the whole shell down.
  // The panel outlives every popup cycle, and hands the keys on from there.
  readonly property alias keySink: panel
  readonly property Item innerFocus: {
    const f = panel.Window.activeFocusItem
    return f && f !== panel ? f : null
  }

  anchor.item: root.lastAnchor

  color: "transparent"
  // The compositor's own xdg-popup keyboard grab fights the Hyprland focus grab
  // below once that grab also covers the bar: the popup takes the keyboard, the
  // focus grab is cancelled the same frame and the popup closes itself. Hypr's
  // grab does the dismissal; the bar forwards the keys.
  grabFocus: false
  implicitWidth: root.panelWidth + root.gutterX * 2
  implicitHeight: panel.implicitHeight + root.gutterTop + root.gutterBottom
  visible: root.open || panel.opacity > 0
  // Only the panel takes pointer input, or the transparent gutter would swallow
  // both the outside click that dismisses this and the clicks meant for the
  // windows below.
  mask: Region { item: panel }

  HyprlandFocusGrab {
    id: grab
    windows: root.grabAnchorWindow && root.lastAnchor
      ? [root, root.lastAnchor.QsWindow.window]
      : [root]
    onCleared: PopoverManager.close()
  }

  // The compositor refuses a grab requested in the same frame the surface is
  // mapped and `active` silently stays false -- which looks exactly like a
  // popup that never closes. One frame of delay is enough.
  //
  // Armed off `open`, never off `visible`: the window stays mapped through the
  // fade-out, so closing and reopening inside that window never dips `visible`
  // false→true and a Timer running off it would not re-fire -- leaving the
  // reopened popup with no grab and no way to dismiss it.
  Timer {
    id: armTimer
    interval: 1
    onTriggered: grab.active = root.open
  }

  onOpenChanged: {
    if (root.open) {
      if (root.anchorItem) root.lastAnchor = root.anchorItem
      armTimer.restart()
      PopoverManager.keySink = panel
    } else {
      grab.active = false
      if (PopoverManager.keySink === panel) PopoverManager.keySink = null
    }
  }

  // A menu bar switches menus with this popup already up.
  onAnchorItemChanged: if (root.open && root.anchorItem) root.lastAnchor = root.anchorItem

  // Shadow only -- nothing paints the panel into it, so the glass above stays
  // translucent and Hyprland's blur still has something to work on.
  RectangularShadow {
    anchors.fill: panel
    radius: panel.radius
    color: Theme.panelShadowColor
    opacity: panel.opacity
    offset.y: root.shadowOffset
    blur: root.shadowBlur
    z: -1
  }

  GlassPanel {
    id: panel

    x: root.gutterX
    y: root.gutterTop
    width: root.panelWidth
    implicitHeight: root.panelHeight
    radius: root.panelRadius

    opacity: root.fade && !root.open ? 0 : 1
    scale: root.fade && !root.open ? 0.96 : 1
    transformOrigin: Item.Top

    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    focus: true
    Keys.onEscapePressed: PopoverManager.close()
    // Whatever inside the panel actually holds focus. Bound, not stored, so a
    // delegate that is destroyed under it drops out of the list.
    Keys.forwardTo: root.innerFocus ? [root.innerFocus] : []
  }
}
