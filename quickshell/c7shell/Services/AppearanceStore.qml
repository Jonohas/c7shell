pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Spec §7: ~/.config/hypr/appearance.json is the single source of truth for
// look-and-feel. The settings app writes `values`, JsonAdapter persists them,
// and this singleton pushes them at the compositor. conf/look-and-feel.lua
// reads the same file at config load, so a value survives both a hyprland
// reload and a qs restart. Hand-edits arrive through watchChanges.
//
// This is a service, so the Process calls belong here and nowhere else.
Singleton {
  id: root

  // Settings pages assign straight to this — writes persist themselves.
  readonly property alias values: adapter

  // -- clamped reads --------------------------------------------------------
  // Everything that leaves this file goes through these, never through the
  // adapter: the JSON is hand-editable, so its contents are untrusted input
  // and a stray value must not reach a Lua eval or wedge the compositor.
  // "light" is deliberately absent: Theme has no light palette yet, so
  // accepting it would persist a variant nothing can render. The card is
  // shown disabled rather than silently doing nothing when picked.
  readonly property string theme: ["dark", "oled"].includes(root.values.theme) ? root.values.theme : "dark"
  readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(root.values.accent) ? root.values.accent : "#e53a44"
  readonly property bool fromWallpaper: root.values.fromWallpaper

  readonly property int rounding: root.clamp(root.values.rounding, 0, 40)
  readonly property int gapsIn: root.clamp(root.values.gapsIn, 0, 40)
  readonly property int gapsOut: root.clamp(root.values.gapsOut, 0, 60)
  readonly property int blurSize: root.clamp(root.values.blurSize, 1, 20)
  readonly property int blurPasses: root.clamp(root.values.blurPasses, 1, 5)
  readonly property real inactiveOpacity: root.clamp(root.values.inactiveOpacity, 0.3, 1)
  readonly property int borderWidth: root.clamp(root.values.borderWidth, 0, 10)
  // Active border is the accent (spec §7); only the inactive one is a choice.
  readonly property color inactiveBorder: /^#[0-9a-fA-F]{6}$/.test(root.values.inactiveBorder)
    ? root.values.inactiveBorder : "#595959"
  readonly property bool animationsEnabled: root.values.animationsEnabled
  readonly property real animationSpeed: root.clamp(root.values.animationSpeed, 0.25, 4)
  readonly property string wallpaper: root.values.wallpaper
  // The cursor name reaches a directory lookup, two config files and an argv
  // element in the exporter, so it is held to a plain theme name here too.
  readonly property string cursorTheme: /^[A-Za-z0-9._-]+$/.test(root.values.cursorTheme)
    ? root.values.cursorTheme : "Adwaita"
  readonly property int cursorSize: root.clamp(root.values.cursorSize, 8, 128)

  function clamp(v, lo, hi) {
    const n = Number(v)
    return isNaN(n) ? lo : Math.max(lo, Math.min(hi, n))
  }

  // The four alternates from the mock, oklch(0.62 0.19 h) for h ∈
  // {25,300,230,150}, converted once here rather than at every repaint. 230 and
  // 150 fall outside sRGB at that chroma and are gamut-mapped the way CSS
  // Color 4 does it, so the swatches match the mockup rendered in a browser.
  readonly property var accentChoices: ["#e53a44", "#e24947", "#9964e5", "#1692c0", "#00a149"]
  // Inactive borders are the quiet half of the pair: neutrals, plus the accent
  // itself for anyone who wants both borders tinted.
  readonly property var borderChoices: ["#2a2a2e", "#595959", "#8b8b93", "#e53a44"]

  // -- persistence ----------------------------------------------------------
  FileView {
    id: file

    path: `${Quickshell.env("HOME")}/.config/hypr/appearance.json`
    watchChanges: true
    // First run has no file; that is expected, not something to warn about.
    printErrors: false

    onFileChanged: file.reload()
    onAdapterUpdated: file.writeAdapter()
    onLoaded: { apply.restart(); kdeExport.restart() }
    // Write the defaults out so hyprland has something to read on its next
    // config load, instead of both sides silently disagreeing.
    onLoadFailed: err => { if (err === FileViewError.FileNotFound) file.writeAdapter() }

    JsonAdapter {
      id: adapter

      property string theme: "dark"
      property string accent: "#e53a44"
      property bool fromWallpaper: false
      property int rounding: 19
      property int gapsIn: 3
      property int gapsOut: 12
      property int blurSize: 8
      property int blurPasses: 3
      property real inactiveOpacity: 1.0
      property int borderWidth: 2
      property string inactiveBorder: "#595959"
      property bool animationsEnabled: true
      property real animationSpeed: 1.0
      property string wallpaper: ""
      // Not exposed in the settings app yet; they live here so a hand-edit
      // survives the next write instead of being dropped from the JSON.
      property string cursorTheme: "Adwaita"
      property int cursorSize: 24
    }
  }

  // -- live apply -----------------------------------------------------------
  // A slider drag changes the value every frame; coalesce into one hyprctl.
  Timer {
    id: apply
    interval: 120
    onTriggered: root.applyNow()
  }

  onRoundingChanged: apply.restart()
  onGapsInChanged: apply.restart()
  onGapsOutChanged: apply.restart()
  onBlurSizeChanged: apply.restart()
  onBlurPassesChanged: apply.restart()
  onInactiveOpacityChanged: apply.restart()
  onBorderWidthChanged: apply.restart()
  onAnimationsEnabledChanged: apply.restart()
  onAnimationSpeedChanged: apply.restart()
  onAccentChanged: { apply.restart(); kdeExport.restart() }
  onThemeChanged: kdeExport.restart()
  // The exporter is what carries a cursor change to kcminputrc, both GTK
  // settings.ini files and `hyprctl setcursor`; the compositor's own env is
  // read by conf/environment.lua at config load.
  onCursorThemeChanged: kdeExport.restart()
  onCursorSizeChanged: kdeExport.restart()
  onWallpaperChanged: wallpaperApply.restart()

  // Qt and KDE apps take their colours from ~/.config/kdeglobals, which nothing
  // in this session kept in step with appearance.json -- so the shell went green
  // and dolphin stayed crimson. scripts/c7shell-theme-export.py rewrites the
  // C7Shell scheme from this store's own accent and variant, then emits the
  // signal plasma-integration repaints on. Only accent and theme move it; the
  // geometry sliders have nothing to export.
  //
  // Needs QT_QPA_PLATFORMTHEME=kde (hypr/conf/environment.lua): under qt6ct KDE
  // apps read neither kdeglobals nor qt6ct's palette and come up stock light.
  //
  // Resolved off this file, not off $HOME: the packaged shell lives in
  // /usr/share/c7shell, and a hardcoded ~/.config path would silently export
  // nothing there.
  readonly property string exporter:
    Qt.resolvedUrl("../scripts/c7shell-theme-export.py").toString().replace(/^file:\/\//, "")

  Timer {
    id: kdeExport
    interval: 250
    onTriggered: {
      if (kdeGlobals.running) { kdeExport.restart(); return }
      kdeGlobals.exec(["python3", root.exporter])
    }
  }

  Process {
    id: kdeGlobals
    // The script reads appearance.json itself rather than taking argv, so a
    // hand-edit lands the same way a settings click does.
    stderr: StdioCollector {}
  }

  // Hyprland wants rgba(rrggbbaa); `accent` is already validated hex, and
  // going through Qt.color keeps the conversion honest either way.
  function rgba(c, a) {
    const col = Qt.color(c)
    const h = x => Math.round(x * 255).toString(16).padStart(2, "0")
    return `rgba(${h(col.r)}${h(col.g)}${h(col.b)}${h(a)})`
  }

  // `hyprctl keyword` does not work on this build: the config provider is lua,
  // and Hyprland answers keyword with "can't work with non-legacy parsers, use
  // eval". So live-apply speaks the same hl.config() dialect the config files
  // do (see conf/look-and-feel.lua).
  function luaConfig() {
    return "hl.config({"
      + `general={gaps_in=${root.gapsIn},gaps_out=${root.gapsOut},border_size=${root.borderWidth},`
      + `col={active_border="${root.rgba(root.accent, 238 / 255)}",`
      + `inactive_border="${root.rgba(root.inactiveBorder, 170 / 255)}"}},`
      + `decoration={rounding=${root.rounding},inactive_opacity=${root.inactiveOpacity.toFixed(3)},`
      + `blur={size=${root.blurSize},passes=${root.blurPasses}}},`
      + `animations={enabled=${root.animationsEnabled ? "true" : "false"}}})`
  }

  // Speed is per-animation-leaf in Hyprland — there is no global multiplier
  // keyword. conf/animations.lua returns its leaf table so the multiplier can
  // be re-applied over it without this file duplicating the speeds.
  // ponytail: pcall'd because a hyprland whose animations.lua predates that
  // change simply keeps its configured speeds instead of erroring.
  function luaAnimations() {
    return ";pcall(function() for _,l in ipairs(require('conf/animations')) do"
      + ` hl.animation({leaf=l.leaf,enabled=${root.animationsEnabled ? "true" : "false"},`
      + `speed=l.speed/${root.animationSpeed.toFixed(3)},bezier=l.bezier,spring=l.spring,style=l.style}) end end)`
  }

  function applyNow() {
    if (hypr.running) { apply.restart(); return }
    hypr.exec(["hyprctl", "eval", root.luaConfig() + root.luaAnimations()])
  }

  Process {
    id: hypr
    // A compositor that is not there is not an error worth a toast: the shell
    // can run under a plain nested session while a page is being designed.
    stderr: StdioCollector {}
  }

  // This hyprpaper (0.8.4) implements exactly one request — `wallpaper`, taking
  // [mon],[path],[fit_mode]. `preload` is rejected as an invalid request, and
  // is not needed: a bare wallpaper request loads the file itself (verified —
  // hyprpaper ends up holding an open fd on it) and validates the path,
  // answering "bad path" when it does not exist. An empty monitor field means
  // every monitor. argv, so the path is never parsed by a shell.
  Timer {
    id: wallpaperApply
    interval: 200
    onTriggered: {
      if (root.wallpaper === "" || paper.running) return
      paper.exec(["hyprctl", "hyprpaper", "wallpaper", `,${root.wallpaper}`])
    }
  }

  Process {
    id: paper
    stderr: StdioCollector {}
  }
}
