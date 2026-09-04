import QtQuick
import QtQuick.Effects
import qs.Theme

// The scaffold behind every self-dismissing card in the top-right stack: the
// shadow, the glass, and the countdown. Three toasts had a verbatim copy of it
// and had drifted apart on radius and on whether hovering holds the card open,
// which is visible because the cards stack against each other (#88).
//
// A card, not a window. Two windows in that corner is what once drew two cards
// on top of each other; NotificationToasts.qml is the single host.
Item {
  id: root

  property bool shown: false
  // Milliseconds before the card asks to be dismissed. 0 keeps it up
  // indefinitely -- the escalated update toast is waiting for an answer and
  // must not time out.
  property int life: 0

  // Defaults to the full stack width. The capture card overrides it: it is a
  // pill around a thumbnail, and a 340px one would be mostly empty.
  property real cardWidth: root.width
  property real cardHeight: 0
  property int cardRadius: Theme.radiusCard

  // The countdown ran out. The card does not clear `shown` itself because an
  // owner may have bound it -- FinishedToast binds it to `path !== ""`, and
  // assigning here would break that binding.
  signal timeout()

  default property alias content: card.data

  visible: root.shown
  implicitHeight: root.visible ? card.height : 0

  // Restart the countdown for a card that is already up. A second capture
  // arriving while the first card still shows never changes `shown`, so
  // onShownChanged alone would leave it on the first card's clock.
  function kick() {
    if (root.life > 0 && root.shown)
      countdown.restart()
    else
      countdown.stop()
  }

  onShownChanged: root.kick()

  Timer {
    id: countdown
    // A zero interval would fire immediately rather than never; `life: 0` is
    // handled by kick() refusing to start the timer at all.
    interval: Math.max(1, root.life)
    onTriggered: root.timeout()
  }

  RectangularShadow {
    anchors.fill: card
    radius: card.radius
    color: Theme.panelShadowColor
    offset.y: 12
    blur: 40
    z: -1
  }

  GlassPanel {
    id: card

    anchors { right: parent.right; top: parent.top }
    width: root.cardWidth
    height: root.cardHeight
    radius: root.cardRadius

    MouseArea {   // hovering holds the card open while you aim at an action
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      // Content arrives through the default slot and is therefore declared
      // after this, so it would sit on top and swallow the hover. Clicks still
      // reach it: this area accepts no buttons.
      z: 10
      onEntered: countdown.stop()
      onExited: root.kick()
    }
  }
}
