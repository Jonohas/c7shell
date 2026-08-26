pragma Singleton
import Quickshell
import QtQuick

// Cross-module route to the settings app. Popover footers call open(page);
// the settings window (SP6) connects to openRequested. Until then the
// signal simply has no listener.
Singleton {
  id: root

  signal openRequested(string page)

  function open(page) { root.openRequested(page) }
}
