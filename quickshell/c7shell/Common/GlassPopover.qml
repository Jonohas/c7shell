import QtQuick
import Quickshell
import qs.Theme
import qs.Services

// Base for every bar popover: a PopupSurface hanging under the bar island,
// up while PopoverManager.current names it. Content goes in the default
// property and is laid out in a Column with the panel's own gap; everything
// else about the window -- grab, mask, shadow, fade -- is PopupSurface's.
PopupSurface {
  id: root

  // Matched against PopoverManager.current -- the popover's identity.
  required property string name
  property int padding: 14
  property int gap: 11

  default property alias content: column.data

  open: PopoverManager.current === root.name
  anchorItem: PopoverManager.anchorItem

  // The compositor does not land the surface exactly where the anchor rect asks
  // -- measured, it sits `overshoot` px lower, which rendered the 8px gap as 12.
  // Correcting it on the panel's offset inside the window rather than in the
  // anchor rect keeps the correction deterministic: the rect is a request, the
  // panel's y is not.
  readonly property int overshoot: 8

  // Nominal room for the panel's `0 24px 80px` shadow; the panel is drawn
  // `overshoot` higher inside it, which is where the correction lives.
  readonly property int gutter: 60

  gutterX: root.gutter
  gutterTop: root.gutter - root.overshoot
  gutterBottom: root.gutter + root.overshoot
  panelHeight: column.implicitHeight + root.padding * 2

  // The panel sits 8px under the bar island whichever module opened it, so the
  // anchor point is measured from the bar window's origin instead of from the
  // anchoring item: a 14px status icon and a 26px clock pill then land the
  // panel in exactly the same place. Writing any part of `rect` drops its
  // item-derived default, so all four components are set.
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.rect.x: 0
  anchor.rect.width: root.lastAnchor?.width ?? 0
  anchor.rect.height: 0
  anchor.rect.y: {
    const item = root.lastAnchor
    if (!item) return 0
    return Theme.barMarginTop + Theme.barHeight + 8 - root.gutter - item.mapToItem(null, 0, 0).y
  }

  Column {
    id: column
    anchors {
      top: parent.top; left: parent.left; right: parent.right
      margins: root.padding
    }
    spacing: root.gap
  }
}
