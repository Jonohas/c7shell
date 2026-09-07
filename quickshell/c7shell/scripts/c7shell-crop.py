#!/usr/bin/env python3
"""Cut a rectangle out of a PNG, pixelating anything asked for on the way.

    c7shell-crop.py <src.png> <dst.png> <x> <y> <w> <h>
                    [--block N] [--pixelate X,Y,W,H]...

Coordinates are DEVICE pixels -- pixels of src.png, not the logical pixels
Hyprland and grim -g talk in. The caller knows the ratio between the two
exactly (the frozen frame's own width over the overlay's logical width) and
converting here as well would be one scale factor guessed twice. --pixelate
rectangles are in that same frame, not in the crop: they are drawn on the
still before anything is cut, and the crop is the last thing that happens.

This exists for the delayed screenshot. The delay is for capturing something
that only appears while the pointer is on it -- a hover menu, a tooltip -- so
the region cannot be drawn before the shutter: by the time you move the
pointer to draw it, the thing you wanted is gone. So the shutter goes first,
the whole output is captured, the overlay reopens on that still frame, and the
rectangle drawn there is cut out of the file. grim reads the compositor and
cannot re-crop a file, hence this.

Pixelation is here rather than in the overlay for the same reason as the crop:
the overlay draws a preview of the mosaic, but what it draws is a picture on a
layer surface, and nothing on a layer surface reaches the PNG. The redaction
has to be burnt into the file or it is not a redaction at all -- so the QML
preview and this pass have to agree, which is what --block is for.

gdk-pixbuf, not Pillow: python-gobject is already a hard dependency of the
package and Pillow is not, and this is a subrectangle copy -- not the place to
add one.
"""
import sys

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib  # noqa: E402

# Device pixels per mosaic block when the caller does not say. The overlay
# always says, because it knows the output's scale and this does not.
DEFAULT_BLOCK = 12


def fail(msg):
    print(f"c7shell-crop: {msg}", file=sys.stderr)
    raise SystemExit(1)


def parse_options(argv):
    """The tail after the six positional arguments: --block and --pixelate.

    Hand-rolled rather than argparse: the whole grammar is two flags, and the
    messages here name the value that was wrong, which is what reaches the
    notification when a capture fails.
    """
    block = DEFAULT_BLOCK
    rects = []
    i = 0
    while i < len(argv):
        flag = argv[i]
        if i + 1 >= len(argv):
            fail(f"{flag} takes a value")
        value = argv[i + 1]
        i += 2

        if flag == "--block":
            try:
                block = int(round(float(value)))
            except ValueError:
                fail(f"--block must be a number, got {value}")
            if block < 1:
                fail(f"--block must be at least 1, got {block}")
        elif flag == "--pixelate":
            parts = value.split(",")
            if len(parts) != 4:
                fail(f"--pixelate takes X,Y,W,H, got {value}")
            try:
                rects.append(tuple(int(round(float(p))) for p in parts))
            except ValueError:
                fail(f"--pixelate takes four numbers, got {value}")
        else:
            fail(f"unknown option {flag}")
    return block, rects


def snap_rect(x, y, w, h, block):
    """Grow a rectangle out to whole blocks.

    Half a block of the thing being hidden, left legible along an edge, is the
    one failure a redaction cannot have. Growing also puts the mosaic on the
    same grid the overlay previewed it on -- Modules/Capture/RedactionLayer.qml
    snaps the same way, in logical pixels, because the two cannot share the
    code and can only agree on the rule.
    """
    x0 = (x // block) * block
    y0 = (y // block) * block
    x1 = -(-(x + w) // block) * block
    y1 = -(-(y + h) // block) * block
    return x0, y0, x1 - x0, y1 - y0


def clamp_rect(x, y, w, h, frame_w, frame_h):
    """Trim a rectangle to the frame, or None when nothing of it is left.

    Clamped rather than rejected. The rectangle arrives in logical pixels
    scaled up by a factor that is 1.25 on this laptop, so the edge of a
    selection flush against the edge of the screen rounds a pixel past the
    frame -- which is a one-pixel rounding question, not a reason to lose the
    screenshot.
    """
    x0 = max(0, min(x, frame_w))
    y0 = max(0, min(y, frame_h))
    x1 = max(0, min(x + w, frame_w))
    y1 = max(0, min(y + h, frame_h))
    if x1 - x0 < 1 or y1 - y0 < 1:
        return None
    return x0, y0, x1 - x0, y1 - y0


def pixelate(full, rect, block):
    """Mosaic one rectangle of `full`, in place.

    Down to one pixel per block and straight back up: BILINEAR going down so a
    block is the average of what it covers rather than whichever pixel landed
    on the sample point, NEAREST coming back so the block stays a flat square
    instead of a smear -- a smeared redaction still shows the shape of what it
    covers.
    """
    x, y, w, h = rect
    # new_subpixbuf shares pixels with the parent, so scaling into it writes
    # through to the frame and there is no copy to paste back.
    area = full.new_subpixbuf(x, y, w, h)
    small = area.scale_simple(max(1, w // block), max(1, h // block),
                              GdkPixbuf.InterpType.BILINEAR)
    if small is None:
        fail(f"cannot pixelate {w}x{h} at {x},{y}")
    small.scale(area, 0, 0, w, h, 0, 0,
                w / small.get_width(), h / small.get_height(),
                GdkPixbuf.InterpType.NEAREST)


def main(argv):
    if len(argv) < 7:
        fail(f"expected at least 6 arguments, got {len(argv) - 1}")

    src, dst = argv[1], argv[2]
    try:
        x, y, w, h = (int(round(float(v))) for v in argv[3:7])
    except ValueError:
        fail(f"x y w h must be numbers, got {' '.join(argv[3:7])}")

    block, redactions = parse_options(argv[7:])

    try:
        full = GdkPixbuf.Pixbuf.new_from_file(src)
    except GLib.Error as e:
        fail(f"cannot read {src}: {e.message}")

    frame_w, frame_h = full.get_width(), full.get_height()

    # Before the crop, and on the whole frame: the rectangles were drawn on the
    # still, which is the frame, so a crop first would move every one of them.
    for rect in redactions:
        trimmed = clamp_rect(*snap_rect(*rect, block), frame_w, frame_h)
        # A rectangle entirely off the frame redacts nothing. Dropping it is
        # not a failure -- losing the screenshot over it would be.
        if trimmed is not None:
            pixelate(full, trimmed, block)

    x = max(0, min(x, frame_w - 1))
    y = max(0, min(y, frame_h - 1))
    w = max(1, min(w, frame_w - x))
    h = max(1, min(h, frame_h - y))

    # new_subpixbuf shares pixels with the parent, so savev writes the crop
    # without copying the whole frame a second time.
    try:
        full.new_subpixbuf(x, y, w, h).savev(dst, "png", [], [])
    except GLib.Error as e:
        fail(f"cannot write {dst}: {e.message}")


if __name__ == "__main__":
    main(sys.argv)
