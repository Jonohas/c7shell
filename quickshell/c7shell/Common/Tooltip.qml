import QtQuick
import Quickshell
import qs.Theme

// A hover tooltip: a glass card in a transparent window, hanging under whatever
// the cursor is on. A sibling of PopupSurface rather than a use of it -- the
// masking discipline is the same, but a tooltip wants none of the focus grab,
// the PopoverManager wiring or the fade, which is most of what PopupSurface is.
//
// Owners set `open` off their own hover state and `anchorItem` off the item
// being hovered; the content goes in the default property and is parented to
// the card. As in PopupSurface, owners size their own card -- a Rectangle will
// not do it for them.
PopupWindow {
  id: root

  // Owners drive this rather than `visible`, which is derived from it below.
  property bool open: false

  // The item the tooltip hangs off. Owners usually bind this to whichever
  // delegate is hovered, so one window can serve a whole row of them.
  property Item anchorItem: null

  // Room around the card, so it clears the bar it drops out of rather than
  // sitting flush against it.
  property int gutterX: 12
  property int gutterY: 6

  property int panelWidth: 200
  property real panelHeight: 0
  property int panelRadius: Theme.radiusMenu

  default property alias content: card.data
  readonly property alias panel: card

  grabFocus: false
  color: "transparent"
  // An anchorless tooltip has nowhere to be. Mapping it anyway leaves a card
  // parked in the corner of the screen with no way to dismiss it, so the anchor
  // is part of the show condition rather than something owners must remember.
  visible: root.open && root.anchorItem !== null
  implicitWidth: root.panelWidth + root.gutterX * 2
  implicitHeight: card.implicitHeight + root.gutterY * 2
  // Only the card takes pointer input, or the transparent gutter would swallow
  // the clicks meant for the windows below.
  mask: Region { item: card }

  anchor {
    item: root.anchorItem
    edges: Edges.Bottom
    gravity: Edges.Bottom
  }

  GlassPanel {
    id: card

    x: root.gutterX
    y: root.gutterY
    width: root.panelWidth
    implicitHeight: root.panelHeight
    radius: root.panelRadius
  }
}
