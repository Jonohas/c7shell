//@ pragma UseQApplication
// Required for the tray's dbus menus: SystemTrayItem.display() renders a
// platform menu, which only exists under QApplication.

import Quickshell
import qs.Modules.Bar
import qs.Modules.Launcher
import qs.Modules.Capture
import qs.Modules.Popovers
import qs.Modules.Osd
import qs.Modules.Power
import qs.Modules.Settings
import qs.Modules.Updates
import qs.Modules.Wallpaper
import qs.Services

Scope {
  // First, and on the background layer: on most machines this is nothing at
  // all -- hyprpaper owns the wallpaper and Wallpaper.qml maps no windows.
  Wallpaper {}

  Bar {}
  CommandWindow {}
  CaptureOverlay {}

  // One instance each, not per-screen: a popover anchors itself to whichever
  // bar item opened it.
  AudioPopover {}
  WifiPopover {}
  BluetoothPopover {}
  CalendarPopover {}
  UpdatesDropdown {}

  // One instance, like every other popover: it anchors to whichever bar's
  // power button opened it.
  PowerDropdown {}

  // The escalated path's window. Like SettingsWindow it is a Scope around a
  // Loader, so killing the toplevel does not stop it reopening.
  UpdateWizard {}

  // The one top-right toast host: capture card and notification stack.
  NotificationToasts {}

  OsdPill {}
  OsdSources {}   // event sources; without this nothing ever raises a pill

  // One window; SettingsService.openRequested and the "settings" IPC target
  // both route into it. Killing the toplevel does not destroy this object, so
  // reopening works without re-instantiating anything.
  SettingsWindow {}
}
