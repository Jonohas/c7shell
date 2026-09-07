#!/usr/bin/env python3
"""Draw an annotation scene over a screenshot and write the result.

    c7shell-render.py <dst.png> --scene <scene.json>
    c7shell-render.py <dst.png> --scene-json '<json>'

Two ways in for one reason. The shell passes the scene inline, because a
temporary file would have to be written, waited for and cleaned up, and the
wait is the part with no honest answer -- a writer reports that it wrote, not
that another process can read it. Tests pass a file, because a fixture is
easier to read as a file than as a shell quoting exercise.

The editor draws a preview; this writes the file. Those are two different
pictures of the same thing and only one of them is kept, so everything that
decides what the export looks like is here rather than split across the two.

WHY NOT GRAB THE EDITOR'S OWN SCENE GRAPH. What the editor draws is a layer
surface at display scale -- a 3840x2160 shot is on screen at whatever fraction
of that fits between the tool bars, and grabbing it saves that fraction. The
file has to be the source image's own resolution. A screen grab is also
untestable without a compositor, and the one failure this feature cannot have
is a redaction that was in the preview and not in the PNG: you looked at the
mosaic, agreed it covered the token, and saved a file with the token in it.

COORDINATES ARE IMAGE PIXELS -- pixels of the source PNG, the same numbers the
editor stores its objects in. The editor scales for display and converts
nowhere else, so there is exactly one place a scale factor is applied and it is
not this file.

ORDER IS Z-ORDER. Objects are drawn in the order the scene lists them, and
blur and pixelate sample the surface as it stands at that point -- the image
plus whatever has already been drawn over it. That is what they look like in
the editor, where they are a picture of what is underneath.

REDACTIONS GO FIRST. A region marked `redact` is burnt into the base image
before any object is drawn, so no annotation can be sitting under it hiding
pixels that survived. Everything else is destructive on export too, but only
this one is destructive before the drawing starts.

cairo rather than gdk-pixbuf: gdk-pixbuf cannot stroke a line, and the tools
this exists for are lines, arrows, shapes, numbers and text.
"""
import json
import math
import sys

import cairo

USAGE = ("usage: c7shell-render.py <dst.png> "
         "(--scene <scene.json> | --scene-json '<json>')")

# Every object kind this file knows how to draw. A scene naming anything else
# is an error and not a warning: the editor showed an annotation, the export
# would quietly not contain it, and the file still lands in ~/Pictures looking
# finished. A tool added to the editor without an arm here fails loudly on the
# first export instead.
KINDS = ("rect",)


def die(msg):
    print(f"c7shell-render: {msg}", file=sys.stderr)
    sys.exit(1)


def rgba(spec):
    """"#rrggbb" or "#rrggbbaa" -> the 0..1 tuple cairo takes."""
    s = str(spec).lstrip("#")
    if len(s) not in (6, 8):
        die(f"colour {spec!r} is not #rrggbb or #rrggbbaa")
    try:
        v = [int(s[i:i + 2], 16) / 255 for i in range(0, len(s), 2)]
    except ValueError:
        die(f"colour {spec!r} is not hexadecimal")
    return tuple(v) if len(v) == 4 else (*v, 1.0)


def rounded_rect(cr, x, y, w, h, r):
    """A rectangle path, with corners when r is worth having."""
    r = max(0.0, min(r, w / 2, h / 2))
    if r <= 0:
        cr.rectangle(x, y, w, h)
        return
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def draw_rect(cr, o):
    x, y, w, h = (float(o[k]) for k in ("x", "y", "w", "h"))
    # A rectangle dragged right-to-left or bottom-to-top arrives negative. The
    # editor could normalise it, but then two places would have to agree about
    # it; cairo would draw the stroke either way and fill nothing.
    if w < 0:
        x, w = x + w, -w
    if h < 0:
        y, h = y + h, -h
    cr.set_source_rgba(*rgba(o.get("colour", "#ffffff")))
    if o.get("fill"):
        rounded_rect(cr, x, y, w, h, float(o.get("radius", 0)))
        cr.fill()
        return
    stroke = float(o.get("stroke", 2.4))
    # Inset by half the stroke so the drawn edge lands INSIDE the rectangle the
    # editor showed. cairo centres a stroke on its path, so without this a
    # rectangle around the edge of the shot loses its outer half off the frame.
    rounded_rect(cr, x + stroke / 2, y + stroke / 2,
                 max(0.0, w - stroke), max(0.0, h - stroke),
                 float(o.get("radius", 0)))
    cr.set_line_width(stroke)
    cr.set_line_join(cairo.LINE_JOIN_ROUND)
    cr.stroke()


DRAW = {"rect": draw_rect}


def parse_scene(text, where):
    try:
        scene = json.loads(text)
    except json.JSONDecodeError as e:
        die(f"the scene from {where} is not valid JSON: {e}")
    if not isinstance(scene, dict):
        die(f"the scene from {where} is not a JSON object")
    return scene


def read_scene(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return parse_scene(fh.read(), path)
    except OSError as e:
        die(f"cannot read the scene: {e}")


def load_source(scene):
    src = scene.get("source")
    if not src:
        die("the scene names no source image")
    try:
        base = cairo.ImageSurface.create_from_png(src)
    except (OSError, cairo.Error) as e:
        die(f"cannot read the source image {src}: {e}")
    return base


def check_kinds(objects):
    for i, o in enumerate(objects):
        if not isinstance(o, dict):
            die(f"object {i} is not an object")
        kind = o.get("kind")
        if kind not in KINDS:
            die(f"object {i} is a {kind!r}, which this renderer cannot draw.\n"
                "The editor would have shown it and the exported file would not "
                "contain it.")


def crop(surface, box):
    """Trim to `box`, clamped to what the surface actually has."""
    w, h = surface.get_width(), surface.get_height()
    x = max(0, min(int(box.get("x", 0)), w - 1))
    y = max(0, min(int(box.get("y", 0)), h - 1))
    cw = max(1, min(int(box.get("w", w)), w - x))
    ch = max(1, min(int(box.get("h", h)), h - y))
    out = cairo.ImageSurface(cairo.FORMAT_ARGB32, cw, ch)
    cr = cairo.Context(out)
    cr.set_source_surface(surface, -x, -y)
    cr.paint()
    return out


def render(scene, dst):
    base = load_source(scene)
    objects = scene.get("objects", [])
    if not isinstance(objects, list):
        die("the scene's objects are not a list")
    check_kinds(objects)

    # ARGB32 throughout: the source may be opaque, but a half-transparent
    # annotation drawn onto RGB24 loses its alpha against nothing.
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32,
                                 base.get_width(), base.get_height())
    cr = cairo.Context(surface)
    cr.set_source_surface(base, 0, 0)
    cr.paint()

    for o in objects:
        DRAW[o["kind"]](cr, o)

    box = scene.get("crop")
    if isinstance(box, dict):
        surface = crop(surface, box)

    try:
        surface.write_to_png(dst)
    except (OSError, cairo.Error) as e:
        die(f"cannot write {dst}: {e}")


def main(argv):
    if len(argv) != 4 or argv[2] not in ("--scene", "--scene-json"):
        die(USAGE)
    dst, how, what = argv[1], argv[2], argv[3]
    scene = read_scene(what) if how == "--scene" else parse_scene(what, "--scene-json")
    render(scene, dst)


if __name__ == "__main__":
    main(sys.argv)
