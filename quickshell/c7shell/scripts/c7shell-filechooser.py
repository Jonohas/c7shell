#!/usr/bin/env python3
"""Open the desktop's file chooser and print what was picked.

The settings app has no file dialog of its own and should not grow one: this
session already routes org.freedesktop.impl.portal.FileChooser to the kde
backend in hyprland-portals.conf, so every portal-using app on the machine --
dolphin's siblings, browsers, the lot -- shows the same dialog with the same
KIO places sidebar and the same kdeglobals palette. Appearance -> wallpaper ->
"browse" asks for that one too.

Quickshell 0.3.1 has no generic DBus client (Quickshell.Io is processes, files
and sockets), so the call is made here and the result comes back as a line on
stdout. Services/AppearanceStore.qml runs it.

  c7shell-filechooser.py --title "Choose a wallpaper" --accept "Set wallpaper" \
      --images --current-folder ~/Pictures

Exit status is the useful part:
  0  a path was picked, and it is on stdout
  1  the dialog was cancelled or closed
  2  the portal could not be reached, or answered with something unusable

Requires python-dbus and python-gobject, both package dependencies already.
"""

import argparse
import os
import random
import sys
import urllib.parse

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
FILECHOOSER = "org.freedesktop.portal.FileChooser"
REQUEST = "org.freedesktop.portal.Request"

# What hyprpaper can actually load: the formats libhyprgraphics links a decoder
# for -- libpng, libjpeg, libwebp, libjxl and librsvg (`ldd
# /usr/lib/libhyprgraphics.so`), plus its own bmp reader. Naming them as mime
# types rather than globs leaves the case-folding and the long tail of
# extensions (.jpe, .jfif) to the backend's mime database.
IMAGE_TYPES = [
    "image/png",
    "image/jpeg",
    "image/bmp",
    "image/webp",
    "image/jxl",
    "image/svg+xml",
]


def request_path(bus, token):
    """Where the portal will emit this request's Response.

    The path is predictable from the caller's unique name and the token, and it
    has to be, because subscribing only after OpenFile() returns is a race: a
    backend that answers immediately -- or a portal that denies the call
    outright -- emits Response before the reply carrying the handle arrives, and
    the signal is then missed for good. Subscribing first is what the portal
    documentation asks callers to do.
    """
    sender = bus.get_unique_name()[1:].replace(".", "_")
    return "%s/request/%s/%s" % (PORTAL_PATH, sender, token)


def uri_to_path(uri):
    parts = urllib.parse.urlparse(uri)
    if parts.scheme != "file":
        # Anything the portal exports through the document store, or a remote
        # KIO location, arrives as some other scheme. hyprpaper takes a plain
        # path and nothing else, so there is no honest way to use one.
        return None
    return urllib.parse.unquote(parts.path)


def choose(args):
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()
    picked = []

    token = "c7shell%d" % random.randint(0, 2**31)
    path = request_path(bus, token)

    def on_response(code, results):
        # 0 picked, 1 cancelled by the user, 2 ended some other way.
        if code == 0:
            picked.extend(str(u) for u in results.get("uris", []))
        loop.quit()

    bus.add_signal_receiver(
        on_response,
        signal_name="Response",
        dbus_interface=REQUEST,
        bus_name=PORTAL,
        path=path,
    )

    options = {
        "handle_token": token,
        "modal": dbus.Boolean(True),
        "multiple": dbus.Boolean(False),
        "directory": dbus.Boolean(False),
    }
    if args.accept:
        options["accept_label"] = args.accept
    if args.images:
        options["filters"] = dbus.Array(
            [(args.filter_name, dbus.Array([(dbus.UInt32(1), t) for t in IMAGE_TYPES],
                                          signature="(us)"))],
            signature="(sa(us))",
        )
    if args.current_folder:
        folder = os.path.expanduser(args.current_folder)
        if os.path.isdir(folder):
            # ay, and the portal wants it nul-terminated.
            options["current_folder"] = dbus.ByteArray(folder.encode() + b"\0")

    chooser = dbus.Interface(bus.get_object(PORTAL, PORTAL_PATH), FILECHOOSER)
    # parent_window is left empty: exporting the settings window's handle needs
    # xdg-foreign, which quickshell does not expose. The dialog opens unparented,
    # which under Hyprland means it opens on the focused workspace.
    # The signature is spelled out rather than introspected. dbus-python asks
    # the service for it otherwise, and when there is no service to ask it
    # guesses -- then fails to marshal the options dict with a TypeError instead
    # of the DBusException a missing portal should raise.
    handle = str(chooser.OpenFile("", args.title, options, signature="ssa{sv}"))
    if handle != path:
        # Portals before version 2 chose the handle themselves. Listen there too
        # rather than assume; the extra receiver costs nothing.
        bus.add_signal_receiver(
            on_response,
            signal_name="Response",
            dbus_interface=REQUEST,
            bus_name=PORTAL,
            path=handle,
        )

    loop.run()
    return picked


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--title", default="Open file", help="dialog title")
    ap.add_argument("--accept", default="", help="label for the accept button")
    ap.add_argument("--current-folder", default="", help="folder to open in")
    ap.add_argument("--images", action="store_true",
                    help="offer only the image formats hyprpaper can load")
    ap.add_argument("--filter-name", default="Images", help="label for that filter")
    args = ap.parse_args()

    try:
        picked = choose(args)
    except dbus.DBusException as exc:
        # No portal, no backend, or a denied call. The caller has a working
        # desktop without a file chooser; say why on stderr and fail.
        print("file chooser unavailable: %s" % exc.get_dbus_message(), file=sys.stderr)
        return 2

    if not picked:
        return 1

    path = uri_to_path(picked[0])
    if path is None:
        print("the file chooser returned %s, which is not a local file" % picked[0],
              file=sys.stderr)
        return 2

    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
