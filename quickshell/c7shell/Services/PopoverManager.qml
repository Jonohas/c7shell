pragma Singleton
import Quickshell
import QtQuick

// One popover open at a time. Bar modules call toggle(name, anchorItem);
// popover windows bind visibility to `current` and anchor to `anchorItem`.
Singleton {
  id: root

  property string current: ""
  property Item anchorItem: null

  // Where the bar forwards the keys it receives. A popup's focus grab covers
  // the bar as well (so switching popovers takes one click), and Hyprland then
  // hands the keyboard to the BAR surface -- so the bar has to hand it back to
  // whatever holds focus inside the open popup. PopupSurface keeps this
  // pointed at its own focus item.
  property Item keySink: null

  function toggle(name, item) {
    if (root.current === name) root.close()
    else { root.anchorItem = item; root.current = name }
  }

  function close() {
    root.current = ""
    root.anchorItem = null
  }
}
