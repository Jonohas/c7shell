#!/usr/bin/env python3
"""A fake org.freedesktop.portal.Desktop, for tests/test-settings.sh.

Owns the portal's well-known name on whatever bus DBUS_SESSION_BUS_ADDRESS
points at and answers FileChooser.OpenFile with a canned result, so the helper
can be run end to end without a desktop, a backend or a human to click. It
writes the options it was handed to --record as JSON, which is how the test
checks what the helper actually asked for.

  --answer <uri>   respond with this uri
  --code <n>       respond with this code (0 picked, 1 cancelled, 2 other)
  --empty          respond with code 0 and no uris at all
  --delay <ms>     respond that long after OpenFile returns, instead of before
                   it does (the default is the harder case: a Response that
                   overtakes the reply carrying the handle)
"""

import argparse
import json
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"


class Request(dbus.service.Object):
    @dbus.service.signal("org.freedesktop.portal.Request", signature="ua{sv}")
    def Response(self, code, results):
        pass


class Portal(dbus.service.Object):
    def __init__(self, bus, args):
        super().__init__(bus, PORTAL_PATH)
        self.bus = bus
        self.args = args

    @dbus.service.method("org.freedesktop.portal.FileChooser",
                         in_signature="ssa{sv}", out_signature="o", sender_keyword="sender")
    def OpenFile(self, parent, title, options, sender=None):
        record = {
            "parent": str(parent),
            "title": str(title),
            "options": {k: self.plain(v) for k, v in options.items()},
        }
        if self.args.record:
            with open(self.args.record, "w") as fh:
                json.dump(record, fh)

        token = str(options.get("handle_token", "t"))
        path = "%s/request/%s/%s" % (PORTAL_PATH, sender[1:].replace(".", "_"), token)
        request = Request(self.bus, path)

        code = self.args.code
        # The uri is sent whatever the code is, on purpose: a backend that
        # cancels with a leftover path in the results is exactly what the
        # caller's code check is for.
        results = {} if self.args.empty else {
            "uris": dbus.Array([self.args.answer], signature="s")
        }

        def respond():
            request.Response(dbus.UInt32(code), results)
            return False

        if self.args.delay:
            GLib.timeout_add(self.args.delay, respond)
        else:
            respond()
        return path

    @staticmethod
    def plain(value):
        # current_folder is ay; everything else here is a string, a bool or the
        # filter array, and the test only needs to see them, not round-trip them.
        if isinstance(value, (dbus.ByteArray, bytes)):
            return bytes(value).rstrip(b"\0").decode()
        if isinstance(value, dbus.Array):
            # "ay" arrives as an array of dbus.Byte, not as a ByteArray.
            if value.signature == "y":
                return bytes(bytearray(int(b) for b in value)).rstrip(b"\0").decode()
            return [Portal.plain(v) for v in value]
        if isinstance(value, (dbus.Struct, tuple)):
            return [Portal.plain(v) for v in value]
        if isinstance(value, dbus.Boolean):
            return bool(value)
        if isinstance(value, (dbus.UInt32, dbus.Int32)):
            return int(value)
        return str(value)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--answer", default="file:///tmp/picked.png")
    ap.add_argument("--code", type=int, default=0)
    ap.add_argument("--empty", action="store_true")
    ap.add_argument("--delay", type=int, default=0)
    ap.add_argument("--record", default="")
    args = ap.parse_args()

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(PORTAL, bus, do_not_queue=True)
    portal = Portal(bus, args)
    # The test waits for this line rather than sleeping.
    print("ready", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    sys.exit(main())
