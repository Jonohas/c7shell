#!/usr/bin/env python3
"""Crop a PNG in place of a second grim run.

    c7shell-crop.py <src.png> <dst.png> <x> <y> <w> <h>

Coordinates are DEVICE pixels -- pixels of src.png, not the logical pixels
Hyprland and grim -g talk in. The caller knows the ratio between the two
exactly (the frozen frame's own width over the overlay's logical width) and
converting here as well would be one scale factor guessed twice.

This exists for the delayed screenshot. The delay is for capturing something
that only appears while the pointer is on it -- a hover menu, a tooltip -- so
the region cannot be drawn before the shutter: by the time you move the
pointer to draw it, the thing you wanted is gone. So the shutter goes first,
the whole output is captured, the overlay reopens on that still frame, and the
rectangle drawn there is cut out of the file. grim reads the compositor and
cannot re-crop a file, hence this.

gdk-pixbuf, not Pillow: python-gobject is already a hard dependency of the
package and Pillow is not, and this is a subrectangle copy -- not the place to
add one.
"""
import sys

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib  # noqa: E402


def fail(msg):
    print(f"c7shell-crop: {msg}", file=sys.stderr)
    raise SystemExit(1)


def main(argv):
    if len(argv) != 7:
        fail(f"expected 6 arguments, got {len(argv) - 1}")

    src, dst = argv[1], argv[2]
    try:
        x, y, w, h = (int(round(float(v))) for v in argv[3:7])
    except ValueError:
        fail(f"x y w h must be numbers, got {' '.join(argv[3:7])}")

    try:
        full = GdkPixbuf.Pixbuf.new_from_file(src)
    except GLib.Error as e:
        fail(f"cannot read {src}: {e.message}")

    # Clamped rather than rejected. The rectangle arrives in logical pixels
    # scaled up by a factor that is 1.25 on this laptop, so the edge of a
    # selection flush against the edge of the screen rounds a pixel past the
    # frame -- which is a one-pixel rounding question, not a reason to lose
    # the screenshot.
    x = max(0, min(x, full.get_width() - 1))
    y = max(0, min(y, full.get_height() - 1))
    w = max(1, min(w, full.get_width() - x))
    h = max(1, min(h, full.get_height() - y))

    # new_subpixbuf shares pixels with the parent, so savev writes the crop
    # without copying the whole frame a second time.
    try:
        full.new_subpixbuf(x, y, w, h).savev(dst, "png", [], [])
    except GLib.Error as e:
        fail(f"cannot write {dst}: {e.message}")


if __name__ == "__main__":
    main(sys.argv)
