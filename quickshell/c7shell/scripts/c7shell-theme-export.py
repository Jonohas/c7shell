#!/usr/bin/env python3
"""Export the c7shell appearance to the rest of the desktop.

appearance.json owns the accent, the variant and the preferred colour scheme,
and nothing outside the shell reads it: Qt and KDE apps take their colours from
kdeglobals, and every app that asks "is this a dark desktop?" -- GTK, Electron,
Chromium, anything libadwaita -- asks the settings portal, which answers out of
GSettings. Files nothing kept in step, which is why the shell went green while
dolphin stayed crimson, and why apps that detect a scheme all came up light.

Three parts, and the second is the one that is easy to miss:

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
SCHEME_NAME = "C7Shell"

# plasma-integration reads these two out of kcminputrc and hands them to
# libXcursor. Unset, it leaves Qt apps on the "default" theme -- fine only for
# as long as that keeps inheriting the same theme the compositor uses. Keep both
# in step with XCURSOR_THEME/XCURSOR_SIZE in hypr/conf/environment.lua.
CURSOR_THEME = "Adwaita"
CURSOR_SIZE = "24"

# KGlobalSettings::ChangeType, the argument notifyChange takes.
PALETTE_CHANGED = 0
CURSOR_CHANGED = 4

# Theme.qml surfaces, the same two variants it renders. `bg` is the deepest
# layer (item views), `canvas` the window behind them, `glass` the popover base.
VARIANTS = {
    "dark": {"bg": "#0a0a0c", "canvas": "#0f0e10", "glass": "#0f0f13"},
    "oled": {"bg": "#000000", "canvas": "#050506", "glass": "#000000"},
}
TEXT = "#f0eff1"          # Theme.text
POSITIVE = "#4ade80"      # Theme.success
NEGATIVE = "#ff7a6b"
NEUTRAL = "#f0a44a"
DEFAULT_ACCENT = "#e53a44"

# The preferred colour scheme, and what each consumer of it wants to be told.
# "no-preference" is deliberately not offered: it is what this session already
# said by saying nothing, and it is what left every app light.
SCHEMES = {
    # gsettings enum value, gtk-application-prefer-dark-theme
    "dark": ("prefer-dark", "1"),
    "light": ("prefer-light", "0"),
}
DEFAULT_SCHEME = "dark"

# The groups a KDE app resolves a colour set from: (surface, surface the
# alternate row shades off). Everything else in a group is shared, and derived
# once below. `button` is a raised surface, not the window it sits on.
BACKGROUNDS = {
    "Colors:Window": ("canvas", "canvas"),
    "Colors:View": ("bg", "bg"),
    "Colors:Button": ("button", "canvas"),
    "Colors:Tooltip": ("glass", "canvas"),
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
    subprocess.run(
        ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme",
         SCHEMES[scheme][0]],
        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def notify(change=PALETTE_CHANGED):
    """The half that reaches running apps: a plain file write moves no pixels."""
    subprocess.run(
        ["gdbus", "emit", "--session", "--object-path", "/KGlobalSettings",
         "--signal", "org.kde.KGlobalSettings.notifyChange", str(change), "0"],
        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# -- input ------------------------------------------------------------------
# appearance.json is hand-editable, so treat it as untrusted the way
# AppearanceStore's clamped reads do: a stray value falls back, never reaches
# a colour computation.

def read_appearance():
    try:
        with open(APPEARANCE, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        data = {}
    accent = data.get("accent", "")
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(accent)):
        accent = DEFAULT_ACCENT
    variant = data.get("theme")
    scheme = data.get("colorScheme")
    return (accent.lower(),
            variant if variant in VARIANTS else "dark",
            scheme if scheme in SCHEMES else DEFAULT_SCHEME)


def selftest():
    """Anchored on the hand-tuned scheme this replaces (accent #e53a44, dark)."""
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
    assert palette("#f0e14a", "dark")["Colors:Selection"]["ForegroundNormal"] == "0,0,0"
    assert palette("#00a149", "dark")["Colors:Selection"]["ForegroundNormal"] == "255,255,255"

    # Junk in appearance.json must not reach a colour, or a gsettings argv.
    accent, variant, scheme = read_appearance()
    assert re.fullmatch(r"#[0-9a-f]{6}", accent)
    assert variant in VARIANTS
    assert scheme in SCHEMES

    # The preference is a preference: dark is what a detecting app must be told,
    # and picking light must not quietly turn the shell's own palette light.
    assert SCHEMES["dark"] == ("prefer-dark", "1")
    assert SCHEMES["light"] == ("prefer-light", "0")
    # merge_ini writes into files it does not own. The per-device libinput
    # sections in kcminputrc are the ones that would hurt to lose, and their
    # bracketed names are exactly what a careless rewrite mangles.
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "kcminputrc")
        with open(f, "w", encoding="utf-8") as fh:
            fh.write("[Libinput][2362][628][PIXA3854:00 093A:0274 Touchpad]\n"
                     "NaturalScroll=true\n\n[Mouse]\ncursorSize=48\n")
        merge_ini(f, {"Mouse": {"cursorTheme": CURSOR_THEME,
                                "cursorSize": CURSOR_SIZE}})
        text = open(f, encoding="utf-8").read()
        assert "[Libinput][2362][628][PIXA3854:00 093A:0274 Touchpad]" in text, text
        assert "NaturalScroll=true" in text, text
        assert f"cursorTheme={CURSOR_THEME}" in text, text
        assert f"cursorSize={CURSOR_SIZE}" in text, text
        assert "cursorSize=48" not in text, text

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
    merge_ini(KCMINPUTRC, {"Mouse": {"cursorTheme": CURSOR_THEME,
                                     "cursorSize": CURSOR_SIZE}})
    notify()
    notify(CURSOR_CHANGED)


if __name__ == "__main__":
    main()
