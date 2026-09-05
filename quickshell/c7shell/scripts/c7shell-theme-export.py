#!/usr/bin/env python3
"""Export the c7shell appearance to the rest of the desktop.

appearance.json owns the accent, the variant and the preferred colour scheme,
and nothing outside the shell reads it: Qt and KDE apps take their colours from
kdeglobals, and every app that asks "is this a dark desktop?" -- GTK, Electron,
Chromium, anything libadwaita -- asks the settings portal, which answers out of
GSettings. Files nothing kept in step, which is why the shell went green while
dolphin stayed crimson, and why apps that detect a scheme all came up light.

Four parts, and the second is the one that is easy to miss:

  1. Rewrite the C7Shell colour groups in kdeglobals (and the standalone
     .colors file, so re-picking the scheme in systemsettings does not undo
     this) from the same accent + variant Theme.qml derives its own colours
     from. Every other key in kdeglobals is left alone.
  2. Emit org.kde.KGlobalSettings.notifyChange, which plasma-integration
     listens for. Measured on this machine: a plain file write, and
     `kwriteconfig6 --notify` too, change nothing in a running app -- zero
     pixels moved. The signal repaints them live.
  3. Publish the preferred colour scheme where a detecting app looks for it:
     the GSettings key org.gnome.desktop.interface color-scheme, which
     xdg-desktop-portal-gtk reports as org.freedesktop.appearance color-scheme
     over the portal, plus gtk-application-prefer-dark-theme in the GTK
     settings.ini files for GTK3 apps that never ask the portal. This is a
     preference, not a palette: it says which face those apps should wear and
     touches nothing in the shell's own styling.
  4. Write the lock screen's palette to ~/.config/hypr/hyprlock-palette.conf,
     which hypr/hyprlock.conf sources. hyprlang does no variable expansion and
     cannot read JSON, so hyprlock cannot follow appearance.json on its own --
     without this the shell went green and the lock screen stayed crimson.

The Qt half needs QT_QPA_PLATFORMTHEME=kde (see hypr/conf/environment.lua):
under qt6ct none of kdeglobals is read. The portal half needs a portal backend
that implements Settings -- xdg-desktop-portal-gtk; xdph does not.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from configparser import RawConfigParser

HOME = os.path.expanduser("~")
CONFIG = os.environ.get("XDG_CONFIG_HOME") or f"{HOME}/.config"
DATA = os.environ.get("XDG_DATA_HOME") or f"{HOME}/.local/share"

APPEARANCE = f"{CONFIG}/hypr/appearance.json"
KDEGLOBALS = f"{CONFIG}/kdeglobals"
KCMINPUTRC = f"{CONFIG}/kcminputrc"
GTK_SETTINGS = (f"{CONFIG}/gtk-3.0/settings.ini", f"{CONFIG}/gtk-4.0/settings.ini")
SCHEME_FILE = f"{DATA}/color-schemes/C7Shell.colors"
HYPRLOCK_PALETTE = f"{CONFIG}/hypr/hyprlock-palette.conf"
SCHEME_NAME = "C7Shell"

# The shell's palette and its appearance defaults, which used to be a hand-kept
# copy of Theme.qml and of AppearanceStore.qml's JsonAdapter. Resolved off this
# file so it works from the checkout and from /usr/share/c7shell alike, the same
# way AppearanceStore resolves this script.
PALETTE_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                            "palette.json")
with open(PALETTE_FILE, encoding="utf-8") as _f:
    _p = json.load(_f)
PALETTE, DEFAULTS = _p["palette"], _p["defaults"]

# Cursor defaults: appearance.json owns the value, these are only what a missing
# or corrupt file falls back to.
CURSOR_THEME = DEFAULTS["cursorTheme"]
CURSOR_SIZE = DEFAULTS["cursorSize"]

# KGlobalSettings::ChangeType, the argument notifyChange takes.
PALETTE_CHANGED = 0
CURSOR_CHANGED = 4

# Theme.qml surfaces, the same two variants it renders. `bg` is the deepest
# layer (item views), `canvas` the window behind them, `glassBase` the popover
# base.
VARIANTS = PALETTE["variants"]
TEXT = PALETTE["text"]            # Theme.text
POSITIVE = PALETTE["success"]     # Theme.success
NEGATIVE = PALETTE["negative"]
NEUTRAL = PALETTE["neutral"]
DEFAULT_ACCENT = DEFAULTS["accent"]

# The preferred colour scheme, and what each consumer of it wants to be told.
# "no-preference" is deliberately not offered: it is what this session already
# said by saying nothing, and it is what left every app light.
SCHEMES = {
    # gsettings enum value, gtk-application-prefer-dark-theme
    "dark": ("prefer-dark", "1"),
    "light": ("prefer-light", "0"),
}
DEFAULT_SCHEME = DEFAULTS["colorScheme"]

# The groups a KDE app resolves a colour set from: (surface, surface the
# alternate row shades off). Everything else in a group is shared, and derived
# once below. `button` is a raised surface, not the window it sits on.
BACKGROUNDS = {
    "Colors:Window": ("canvas", "canvas"),
    "Colors:View": ("bg", "bg"),
    "Colors:Button": ("button", "canvas"),
    "Colors:Tooltip": ("glassBase", "canvas"),
    "Colors:Header": ("canvas", "canvas"),
    "Colors:Complementary": ("bg", "bg"),
}
ALT_ALPHA = 0.04  # white overlay behind an alternating row (Theme.surface04)


# -- colour helpers ---------------------------------------------------------
# sRGB, no gamma correction: these reproduce the hand-tuned scheme they replace
# (asserted in selftest) and match what Qt does when it flattens Theme's
# rgba(255,255,255,0.04) overlays onto a surface.

def parse(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def fmt(rgb):
    return ",".join(str(max(0, min(255, round(v)))) for v in rgb)


def mix(a, b, t):
    """t of a over (1-t) of b."""
    a, b = parse(a) if isinstance(a, str) else a, parse(b) if isinstance(b, str) else b
    return tuple(x * t + y * (1 - t) for x, y in zip(a, b))


def over(base, t, top=(255, 255, 255)):
    """`top` at alpha t composited on opaque `base` -- Theme's surfaceNN."""
    return mix(top, base, t)


def lighten(c, dl=0.108, sat=0.90):
    """Theme.accentSoft: lift lightness, ease saturation, keep the hue."""
    r, g, b = (v / 255 for v in parse(c))
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2
    d = mx - mn
    s = 0 if d == 0 else d / (1 - abs(2 * l - 1))
    if d == 0:
        h = 0.0
    elif mx == r:
        h = ((g - b) / d) % 6
    elif mx == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    l, s = min(1.0, l + dl), s * sat
    cc = (1 - abs(2 * l - 1)) * s
    x = cc * (1 - abs(h % 2 - 1))
    m = l - cc / 2
    rgb = [(cc, x, 0), (x, cc, 0), (0, cc, x), (0, x, cc), (x, 0, cc), (cc, 0, x)][int(h) % 6]
    return tuple((v + m) * 255 for v in rgb)


def ink_on(c):
    """White or black, whichever reads on `c`. WCAG relative luminance."""
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = parse(c)
    lum = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    return (0, 0, 0) if lum > 0.45 else (255, 255, 255)


# The lock screen's variables, as alpha over an opaque colour -- hyprlock draws
# straight onto the blurred desktop, so every one of them is translucent. Names
# and alphas are the ones hypr/hyprlock.conf was authored with; only where the
# colour comes from is new. `capslock` is Theme.accentSoft, the same lift the
# greeter's card uses.
HYPRLOCK_VARS = (
    ("ink", "text", 0.90),       # clock
    ("ink2", "text", 0.30),      # the line under the field
    ("ink3", "text", 0.34),      # date
    ("ink4", "text", 0.26),      # lock hint, media, status
    ("glass", "glass", 0.70),    # panel
    ("focus", "accent", 0.55),   # the field's focus ring
    ("accent", "accent", 1.0),
    ("capslock", "accentSoft", 0.60),
    ("success", "success", 1.0),
)


# -- palette ----------------------------------------------------------------

def palette(accent, variant):
    """kdeglobals group -> {key: "r,g,b"} for one accent and variant."""
    v = dict(VARIANTS[variant])
    canvas, bg = v["canvas"], v["bg"]
    v["button"] = over(canvas, 0.07)  # Theme.surface07 over the window

    # Theme.text at 0.40 over the window, i.e. Theme.text3 flattened.
    dim = mix(TEXT, canvas, 0.40)
    shared = {
        "ForegroundNormal": TEXT,
        "ForegroundInactive": dim,
        "ForegroundActive": accent,
        "ForegroundLink": lighten(accent),
        "ForegroundVisited": mix(accent, "#000000", 0.72),
        "ForegroundNegative": NEGATIVE,
        "ForegroundNeutral": NEUTRAL,
        "ForegroundPositive": POSITIVE,
        "DecorationFocus": accent,
        "DecorationHover": mix(accent, canvas, 0.28),
    }

    groups = {}
    for group, (surface, alt_surface) in BACKGROUNDS.items():
        groups[group] = dict(shared,
                             BackgroundNormal=v[surface],
                             BackgroundAlternate=over(v[alt_surface], ALT_ALPHA))

    # Inactive window titlebars and headers: same scheme, quieter text. Without
    # this the stale Breeze default (blue) shows through on an unfocused header.
    groups["Colors:Header][Inactive"] = dict(groups["Colors:Header"],
                                             ForegroundNormal=mix(TEXT, canvas, 0.60))

    groups["Colors:Selection"] = dict(
        shared,
        BackgroundNormal=accent,
        BackgroundAlternate=accent,
        ForegroundNormal=ink_on(accent),
        # Selected-but-inactive text: the accent washed out, not grey.
        ForegroundInactive=mix(accent, "#ffffff", 0.40),
    )

    groups["General"] = {"AccentColor": accent}
    groups["WM"] = {
        "activeBackground": canvas,
        "activeForeground": TEXT,
        "inactiveBackground": bg,
        "inactiveForeground": dim,
    }
    out = {g: {k: fmt(parse(x) if isinstance(x, str) else x) for k, x in keys.items()}
           for g, keys in groups.items()}
    # The one value that is a name rather than a colour.
    out["General"]["ColorScheme"] = SCHEME_NAME
    return out


# -- writing ----------------------------------------------------------------

def reader():
    # optionxform=str: KConfig keys are case-sensitive (AccentColor, activeFont).
    cp = RawConfigParser(strict=False)
    cp.optionxform = str
    return cp


def merge_ini(path, groups):
    """Set `groups` in a KConfig file, leaving every other key in it alone.

    kdeglobals and kcminputrc are both shared files this script is one writer
    of: kdeglobals carries the user's fonts and icon theme, kcminputrc carries a
    per-device [Libinput][vid][pid][name] section for every pointer they own.
    Read, set, atomic replace -- never truncate and rewrite.
    """
    cp = reader()
    cp.read(path, encoding="utf-8")
    for group, keys in groups.items():
        if not cp.has_section(group):
            cp.add_section(group)
        for k, v in keys.items():
            cp.set(group, k, v)
    tmp = path + ".c7tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        cp.write(fh, space_around_delimiters=False)
    os.replace(tmp, path)


def write_scheme(groups):
    """The standalone scheme, so systemsettings hands back these same colours."""
    cp = reader()
    for group, keys in groups.items():
        if group in ("General", "WM"):
            continue
        cp.add_section(group)
        for k, v in keys.items():
            cp.set(group, k, v)
    cp.add_section("General")
    cp.set("General", "Name", SCHEME_NAME)
    cp.set("General", "ColorScheme", SCHEME_NAME)
    cp.add_section("WM")
    for k, v in groups["WM"].items():
        cp.set("WM", k, v)
    os.makedirs(os.path.dirname(SCHEME_FILE), exist_ok=True)
    with open(SCHEME_FILE, "w", encoding="utf-8") as fh:
        cp.write(fh, space_around_delimiters=False)


def write_gtk_settings(scheme):
    """gtk-3.0/gtk-4.0 settings.ini, for GTK apps that never ask the portal.

    Only the prefer-dark flag: gtk-theme-name is the user's to pick, and a
    preference is not a licence to overwrite their theme.
    """
    prefer_dark = SCHEMES[scheme][1]
    for path in GTK_SETTINGS:
        cp = reader()
        cp.read(path, encoding="utf-8")
        if not cp.has_section("Settings"):
            cp.add_section("Settings")
        cp.set("Settings", "gtk-application-prefer-dark-theme", prefer_dark)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".c7tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            cp.write(fh, space_around_delimiters=False)
        os.replace(tmp, path)


def quiet(cmd):
    """Run a helper for its side effect only, and never at the cost of the
    files above: a machine with no hyprctl, no gdbus or no running session
    still gets its palette written rather than a traceback.
    """
    try:
        subprocess.run(cmd, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def write_gsettings(scheme):
    """The key the portal answers org.freedesktop.appearance out of.

    Needs a portal backend that implements Settings -- xdg-desktop-portal-gtk;
    xdph does not -- but the key is worth writing either way: GTK4/libadwaita
    apps in the session read it directly. Best-effort: a machine without
    gsettings, without the schema, or without a dconf writer keeps whatever it
    had rather than failing the palette export next to it.
    """
    if not shutil.which("gsettings"):
        return
    quiet(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme",
           SCHEMES[scheme][0]])


def hyprlock_palette(accent, variant):
    """The text of hyprlock-palette.conf for one accent and variant.

    Pure, because it is the one output whose exact bytes are pinned: the file
    it feeds is hyprlang, which has no expansion and no arithmetic, so a name
    that drifts from hyprlock.conf is a widget drawn in hyprlang's fallback
    colour rather than an error anybody sees.
    """
    sources = {
        "text": TEXT,
        "glass": VARIANTS[variant]["glassBase"],
        "accent": accent,
        "accentSoft": lighten(accent),
        "success": POSITIVE,
    }
    width = max(len(n) for n, _, _ in HYPRLOCK_VARS)
    lines = [
        "# Generated by c7shell-theme-export.py from ~/.config/hypr/"
        "appearance.json -- edits are lost.\n",
        "# hypr/hyprlock.conf sources this after its own defaults, and hyprlang\n",
        "# takes the last definition of a variable, so these win.\n",
        f"# accent {accent}, {variant}\n\n",
    ]
    for name, source, alpha in HYPRLOCK_VARS:
        rgb = parse(sources[source]) if isinstance(sources[source], str) else sources[source]
        hexed = "".join(f"{max(0, min(255, round(v))):02x}" for v in rgb)
        lines.append(f"${name:<{width}} = rgba({hexed}{int(alpha * 255 + 0.5):02x})\n")
    return "".join(lines)


def write_hyprlock_palette(accent, variant):
    """The lock screen's half. hyprlock re-reads its config on every lock, so
    writing the file is the whole of it -- there is nothing running to notify.
    """
    os.makedirs(os.path.dirname(HYPRLOCK_PALETTE), exist_ok=True)
    tmp = HYPRLOCK_PALETTE + ".c7tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(hyprlock_palette(accent, variant))
    os.replace(tmp, HYPRLOCK_PALETTE)


def write_cursor(theme, size):
    """One cursor theme, every consumer that has its own opinion of it.

    Three toolkits, three files, and nothing kept them in step: the compositor
    read XCURSOR_THEME (unset, so it fell through to Adwaita via
    default-cursors), plasma-integration read cursorTheme from kcminputrc
    (unset, so the same fallback), and GTK read gtk-cursor-theme-name from its
    own settings.ini (breeze_cursors) -- two different cursors on one screen.

    hypr/conf/environment.lua sets the compositor's env from the same
    appearance.json key at config load, so the only thing left to reach here is
    the session already running.
    """
    merge_ini(KCMINPUTRC, {"Mouse": {"cursorTheme": theme, "cursorSize": str(size)}})
    for path in GTK_SETTINGS:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        merge_ini(path, {"Settings": {"gtk-cursor-theme-name": theme,
                                      "gtk-cursor-theme-size": str(size)}})
    # Hyprland took XCURSOR_THEME at config load; this is what moves the cursor
    # already on screen. Silent when there is no compositor to talk to.
    quiet(["hyprctl", "setcursor", theme, str(size)])


def notify(change=PALETTE_CHANGED):
    """The half that reaches running apps: a plain file write moves no pixels."""
    quiet(["gdbus", "emit", "--session", "--object-path", "/KGlobalSettings",
           "--signal", "org.kde.KGlobalSettings.notifyChange", str(change), "0"])


# -- input ------------------------------------------------------------------
# appearance.json is hand-editable, so treat it as untrusted the way
# AppearanceStore's clamped reads do: a stray value falls back, never reaches
# a colour computation.

def load_appearance():
    """appearance.json as a dict, or empty when it is missing or malformed."""
    try:
        with open(APPEARANCE, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        data = {}
    return data if isinstance(data, dict) else {}


def cursor_from(data):
    """Validated (theme, size). Pure, so the selftest can reach it.

    The name becomes a directory lookup, a config value and an argv element, so
    it is held to a plain theme name -- a hand-edited "../something" must not
    reach any of the three.
    """
    theme = data.get("cursorTheme")
    if not (isinstance(theme, str) and re.fullmatch(r"[A-Za-z0-9._-]+", theme)):
        theme = CURSOR_THEME
    try:
        size = int(data.get("cursorSize", CURSOR_SIZE))
    except (TypeError, ValueError):
        size = CURSOR_SIZE
    if isinstance(data.get("cursorSize"), bool) or not 8 <= size <= 128:
        size = CURSOR_SIZE
    return theme, size


def read_appearance():
    data = load_appearance()
    accent = data.get("accent", "")
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(accent)):
        accent = DEFAULT_ACCENT
    variant = data.get("theme")
    scheme = data.get("colorScheme")
    return (accent.lower(),
            variant if variant in VARIANTS else "dark",
            scheme if scheme in SCHEMES else DEFAULT_SCHEME)


def selftest():
    """Anchored on the hand-tuned scheme this replaces (default accent, dark)."""
    g = palette(DEFAULT_ACCENT, "dark")
    exact = {
        ("Colors:Button", "BackgroundNormal"): "32,31,33",
        ("Colors:Window", "BackgroundNormal"): "15,14,16",
        ("Colors:Window", "BackgroundAlternate"): "25,24,26",
        ("Colors:View", "BackgroundNormal"): "10,10,12",
        ("Colors:View", "BackgroundAlternate"): "20,20,22",
        ("Colors:Tooltip", "BackgroundNormal"): "15,15,19",
        ("Colors:Window", "ForegroundInactive"): "105,104,106",
        ("Colors:Window", "DecorationHover"): "75,26,31",
        ("Colors:Selection", "BackgroundNormal"): "229,58,68",
        ("Colors:Selection", "ForegroundNormal"): "255,255,255",
        ("Colors:Selection", "ForegroundInactive"): "245,176,180",
        ("Colors:Window", "ForegroundPositive"): "74,222,128",
        ("WM", "activeBackground"): "15,14,16",
    }
    for (group, key), want in exact.items():
        got = g[group][key]
        assert got == want, f"{group}/{key}: {got} != {want}"

    # Link and visited are formula-derived where the old file was hand-picked;
    # near is the contract, not equality.
    def near(group, key, want, tol=8):
        got = [int(x) for x in g[group][key].split(",")]
        exp = [int(x) for x in want.split(",")]
        assert all(abs(a - b) <= tol for a, b in zip(got, exp)), f"{group}/{key}: {got} vs {want}"

    near("Colors:Window", "ForegroundLink", "236,107,115")
    near("Colors:Window", "ForegroundVisited", "165,45,52")

    # oled bottoms out at black, and a light accent takes dark ink.
    assert palette(DEFAULT_ACCENT, "oled")["Colors:View"]["BackgroundNormal"] == "0,0,0"
    # Accents the palette does not offer, on purpose: what decides the ink is
    # the luminance of whatever accent arrives, not a lookup.
    assert palette("#f0e14a", "dark")["Colors:Selection"]["ForegroundNormal"] == "0,0,0"  # palette-literal-ok
    assert palette("#00a149", "dark")["Colors:Selection"]["ForegroundNormal"] == "255,255,255"  # palette-literal-ok

    # The lock screen's palette, anchored on the block it replaces in
    # hyprlock.conf: nine variables, byte for byte, at the default accent.
    text = hyprlock_palette(DEFAULT_ACCENT, "dark")
    for want in ("$ink      = rgba(f0eff1e6)",
                 "$ink2     = rgba(f0eff14d)",
                 "$ink3     = rgba(f0eff157)",
                 "$ink4     = rgba(f0eff142)",
                 "$glass    = rgba(0f0f13b3)",
                 "$focus    = rgba(e53a448c)",
                 "$accent   = rgba(e53a44ff)",
                 "$capslock = rgba(e5717899)",
                 "$success  = rgba(4ade80ff)"):
        assert want in text, f"{want!r} not in:\n{text}"
    # oled bottoms out at black behind the panel, and the ink does not move.
    assert "$glass    = rgba(000000b3)" in hyprlock_palette(DEFAULT_ACCENT, "oled")
    assert "$ink      = rgba(f0eff1e6)" in hyprlock_palette(DEFAULT_ACCENT, "oled")
    # Another accent moves the three variables that are the accent, and only
    # those: this is the whole feature -- a green desktop with a crimson lock
    # screen is what the file it replaces did.
    green = hyprlock_palette("#00a149", "dark")  # palette-literal-ok: an arbitrary accent
    assert "$accent   = rgba(00a149ff)" in green, green
    assert "$focus    = rgba(00a1498c)" in green, green
    assert "$capslock = rgba(0bcd6399)" in green, green
    assert "e53a44" not in green, green
    # hyprlang takes rgba() as exactly eight hex digits: a short or a long one
    # is a config error on the widget that uses it.
    for line in green.splitlines():
        if line.startswith("$"):
            assert re.fullmatch(r"\$[a-z0-9]+ +=+ rgba\([0-9a-f]{8}\)", line), line

    # Junk in appearance.json must not reach a colour, or a gsettings argv.
    accent, variant, scheme = read_appearance()
    assert re.fullmatch(r"#[0-9a-f]{6}", accent)
    assert variant in VARIANTS
    assert scheme in SCHEMES

    # The preference is a preference: dark is what a detecting app must be told,
    # and picking light must not quietly turn the shell's own palette light.
    assert SCHEMES["dark"] == ("prefer-dark", "1")
    assert SCHEMES["light"] == ("prefer-light", "0")
    # sections in kcminputrc are the ones that would hurt to lose, and their
    # A hand-edited cursor name reaches a directory lookup, two config files and
    # an argv element, so it is the one appearance.json value worth fuzzing.
    assert cursor_from({}) == (CURSOR_THEME, CURSOR_SIZE)
    assert cursor_from({"cursorTheme": "Sweet-cursors", "cursorSize": 32}) \
        == ("Sweet-cursors", 32)
    for bad in ("", "../Adwaita", "a b", "x/y", "$(id)", None, 5, True, ["A"]):
        assert cursor_from({"cursorTheme": bad})[0] == CURSOR_THEME, repr(bad)
    for bad in ("huge", None, 0, 7, 129, True, False, [24], 1e9):
        assert cursor_from({"cursorSize": bad})[1] == CURSOR_SIZE, repr(bad)
    assert cursor_from({"cursorSize": "32"})[1] == 32  # JSON strings are common

    # merge_ini writes into files it does not own. kcminputrc's per-device
    # libinput sections are the ones that would hurt to lose -- their bracketed
    # names are exactly what a careless rewrite mangles -- and settings.ini
    # carries a dozen GTK keys this script has no business touching.
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "kcminputrc")
        with open(f, "w", encoding="utf-8") as fh:
            fh.write("[Libinput][2362][628][PIXA3854:00 093A:0274 Touchpad]\n"
                     "NaturalScroll=true\n\n[Mouse]\ncursorSize=48\n")
        merge_ini(f, {"Mouse": {"cursorTheme": CURSOR_THEME,
                                "cursorSize": str(CURSOR_SIZE)}})
        text = open(f, encoding="utf-8").read()
        assert "[Libinput][2362][628][PIXA3854:00 093A:0274 Touchpad]" in text, text
        assert "NaturalScroll=true" in text, text
        assert f"cursorTheme={CURSOR_THEME}" in text, text
        assert f"cursorSize={CURSOR_SIZE}" in text, text
        assert "cursorSize=48" not in text, text

        g = os.path.join(d, "settings.ini")
        with open(g, "w", encoding="utf-8") as fh:
            fh.write("[Settings]\ngtk-theme-name=Breeze\n"
                     "gtk-font-name=Noto Sans,  10\n"
                     "gtk-cursor-theme-name=breeze_cursors\n")
        merge_ini(g, {"Settings": {"gtk-cursor-theme-name": CURSOR_THEME,
                                   "gtk-cursor-theme-size": str(CURSOR_SIZE)}})
        text = open(g, encoding="utf-8").read()
        assert "gtk-theme-name=Breeze" in text, text
        assert "gtk-font-name=Noto Sans,  10" in text, text   # commas, spaces
        assert f"gtk-cursor-theme-name={CURSOR_THEME}" in text, text
        assert "breeze_cursors" not in text, text

    print("selftest ok")


def main():
    if "--selftest" in sys.argv:
        selftest()
        return
    accent, variant, scheme = read_appearance()
    groups = palette(accent, variant)
    merge_ini(KDEGLOBALS, groups)
    write_scheme(groups)
    write_gtk_settings(scheme)
    write_gsettings(scheme)
    write_hyprlock_palette(accent, variant)
    write_cursor(*cursor_from(load_appearance()))
    notify()
    notify(CURSOR_CHANGED)


if __name__ == "__main__":
    main()
