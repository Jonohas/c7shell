//@ pragma UseQApplication
// Required for the tray's dbus menus: SystemTrayItem.display() renders a
// platform menu, which only exists under QApplication.

import Quickshell
import Quickshell.Io
import qs.Modules.Bar
import qs.Modules.Launcher
import qs.Modules.Capture
import qs.Modules.Popovers
import qs.Modules.Osd
import qs.Modules.Settings
import qs.Services

Scope {
  Bar {}
  CommandWindow {}
  CaptureOverlay {}
  FinishedToast {}

  // One instance each, not per-screen: a popover anchors itself to whichever
  // bar item opened it.
  AudioPopover {}
  WifiPopover {}
  BluetoothPopover {}
  CalendarPopover {}

  NotificationToasts {}

  OsdPill {}
  OsdSources {}   // event sources; without this nothing ever raises a pill

  // One window; SettingsService.openRequested and the "settings" IPC target
  // both route into it. Killing the toplevel does not destroy this object, so
  // reopening works without re-instantiating anything.
  SettingsWindow {}

  IpcHandler {
    target: "popover"
    function current(): string { return PopoverManager.current }
  }
}
