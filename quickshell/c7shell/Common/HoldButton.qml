import QtQuick
import qs.Theme

// Press-and-hold to confirm (spec "Interactions": destructive actions get a fill
// animation instead of a dialog). The crimson bar sweeps left to right over
// holdMs and held() fires only when the sweep completes -- any release, or the
// pointer leaving, resets it to zero.
//
// Draws the sweep and nothing else: put the row's own background behind this
// item and its label/icons after it as siblings, so the sweep paints between the
// two. It holds no content of its own.
Item {
  id: root

  property int holdMs: 800
  property color fillColor: Theme.accent
  property real fillRadius: Theme.radiusChip
  readonly property bool holding: sweep.running
  signal held()

  // Whether this button is still on screen and able to be released. The owner
  // binds it to whatever actually changes when the surface goes away -- for a
  // dropdown, its window's `visible`. Do not infer this from the item: an Item
  // inside a Window keeps both `visible` and `activeFocus` when that Window is
  // hidden (measured, Qt 6.11.2), so an item-level guard never runs.
  property bool live: true

  activeFocusOnTab: true

  Rectangle {
    id: sweep_fill
    height: parent.height
    width: 0
    radius: root.fillRadius
    color: root.fillColor
  }

  NumberAnimation {
    id: sweep
    target: sweep_fill
    property: "width"
    from: 0
    to: root.width
    duration: root.holdMs
    onFinished: {
      sweep_fill.width = 0
      root.held()
    }
  }

  function begin() { if (!sweep.running) sweep.restart() }
  function cancel() { sweep.stop(); sweep_fill.width = 0 }

  // Stopping the sweep is not optional bookkeeping: a hold abandoned mid-way --
  // the dropdown dismissed by a focus grab, the window unmapped, focus moving
  // away -- must not run to completion and fire held(), which on the shutdown
  // row is an uncommanded poweroff. `live` is the guard that provably fires;
  // the focus one only covers the row that actually holds focus, and the mouse
  // handlers below cover the pointer.
  onLiveChanged: if (!root.live) root.cancel()
  onActiveFocusChanged: if (!root.activeFocus) root.cancel()

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onPressed: root.begin()
    onReleased: root.cancel()
    onCanceled: root.cancel()
    onExited: root.cancel()
  }

  // Holding a key repeats it, and Qt delivers a press/release pair per repeat --
  // without the isAutoRepeat filter the sweep would restart every few ms and
  // never finish.
  Keys.onPressed: event => {
    if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return
    if (!event.isAutoRepeat) root.begin()
    event.accepted = true
  }
  Keys.onReleased: event => {
    if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return
    if (!event.isAutoRepeat) root.cancel()
    event.accepted = true
  }
}
