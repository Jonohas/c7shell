pragma Singleton
import Quickshell
import QtQuick
import qs.Services

// All design tokens from the c7shell spec §4. Views take every color, radius,
// size and font from here — no literals in views.
//
// Nothing under Services/ imports qs.Theme, so importing the store here is not
// an import cycle.
Singleton {
  id: root

  // -- color --
  // spec §7: the theme variant and the accent are owned by appearance.json,
  // not by this file. Writes from the settings app land here instantly.
  //
  // What each variant IS lives in palette.json, which the exporter, the hypr
  // configs and the greeter read too -- this file holds no colour literals, and
  // tests/test-qml-hygiene.sh keeps it that way.
  readonly property var variant: PaletteStore.palette.variants?.[AppearanceStore.theme]
    ?? PaletteStore.palette.variants?.dark ?? ({})
  readonly property color bg: root.variant.bg
  readonly property color canvas: root.variant.canvas
  // glass base; use with glassAlpha per surface (.68–.82 range in spec)
  readonly property color glassBase: root.variant.glassBase
  readonly property real glassAlphaBar: 0.78
  readonly property real glassAlphaPanel: 0.80

  readonly property color surface04: Qt.rgba(1, 1, 1, 0.04)
  readonly property color surface05: Qt.rgba(1, 1, 1, 0.05)
  readonly property color surface07: Qt.rgba(1, 1, 1, 0.07)
  readonly property color hairline: Qt.rgba(1, 1, 1, 0.08)
  readonly property color hairlineStrong: Qt.rgba(1, 1, 1, 0.10)

  // The store clamps anything the JSON offers back to palette.json's default.
  readonly property color accent: AppearanceStore.accent
  // Was a literal: same hue, 0.9x saturation, +0.108 lightness. Reproduces the
  // hand-picked soft crimson for the default accent and lifts any other alike.
  readonly property color accentSoft: Qt.hsla(root.accent.hslHue,
                                              root.accent.hslSaturation * 0.90,
                                              Math.min(1, root.accent.hslLightness + 0.108), 1)
  readonly property color accentFill: root.alpha(root.accent, 0.14)
  readonly property color accentBorder: root.alpha(root.accent, 0.30)
  readonly property color accentGlow: root.alpha(root.accent, 0.50)

  readonly property color surface10: Qt.rgba(1, 1, 1, 0.10)             // slider tracks (1g)
  readonly property color accentFillSoft: root.alpha(root.accent, 0.11)  // active device row (1g)
  readonly property color accentBorderSoft: root.alpha(root.accent, 0.22) // its border (1g)
  readonly property color accentSoftFill: root.alpha(root.accentSoft, 0.70) // input slider fill (1g)
  readonly property color sliderGlowColor: root.alpha(root.accent, 0.40) // §Geometry: glow 0 0 12px

  // handoff2 quick-settings interaction tokens
  readonly property color hoverPill: Qt.rgba(1, 1, 1, 0.09)               // icon hover pill
  readonly property color accentFillActive: root.alpha(root.accent, 0.16) // open-popover pill
  readonly property color powerHover: root.alpha(root.accent, 0.28)       // power button hover
  readonly property int radiusSlot: 8                                     // 24x22 hit-target pill

  readonly property color text: PaletteStore.palette.text
  // The same ink at the four weights the spec gives it. Derived rather than
  // listed, so a change to `text` carries to all of them.
  readonly property color text2: root.alpha(root.text, 0.55)
  readonly property color text3: root.alpha(root.text, 0.40)
  readonly property color textDisabled: root.alpha(root.text, 0.28)
  // Ink ON an accent or otherwise selected surface. Pure white, not `text`,
  // which reads grey on crimson -- which is why five files had it as a literal.
  readonly property color textOnAccent: PaletteStore.palette.textOnAccent
  readonly property color success: PaletteStore.palette.success
  // The "needs attention, but nothing is broken" amber: a pacnew waiting to be
  // reviewed, and tuned not running. Four views had this literal before the
  // power page needed a fifth.
  readonly property color warning: PaletteStore.palette.warning

  // A well recessed INTO a panel rather than a surface raised onto it: the
  // update run's log scroller is the only one so far.
  readonly property color wellFill: Qt.rgba(0, 0, 0, 0.28)

  // spec §4 shadows: bar `0 12px 40px rgba(0,0,0,.5)`, panels `0 24px 80px rgba(0,0,0,.65)`
  readonly property color barShadowColor: Qt.rgba(0, 0, 0, 0.5)
  readonly property color panelShadowColor: Qt.rgba(0, 0, 0, 0.65)

  // -- geometry --
  readonly property int radiusBar: 19
  readonly property int radiusPanel: 18
  readonly property int radiusRow: 12
  readonly property int radiusChip: 9
  readonly property int radiusPip: 7
  readonly property int radiusWindow: 20   // 1c command window; §4 "panels/windows 18–20"
  readonly property int radiusTile: 10     // 1c 32px result icon tile; §4 "rows/tiles 10–14"
  readonly property int radiusKbd: 6       // 1c "esc" / "↵" kbd chips
  readonly property int radiusCard: 14     // month card (1d), toast card
  readonly property int radiusMenu: 13     // global menu dropdown panel
  readonly property int radiusMenuRow: 8   // its rows, and the bar label hover pill
  readonly property int radiusPreview: 13  // 2b theme preview cards
  readonly property int radiusThumb: 8     // 2b wallpaper thumbnail
  // bar pill vocabulary: clock, recording island, status, tray all share this
  readonly property int pillHeight: 26
  readonly property int pillRadius: 13
  readonly property int barHeight: 38
  // The island's inset from the screen edges, owned by appearance.json like the
  // theme and the accent are: the bar, its shadow gutter, the popover gutter and
  // the toast column all measure off these, so a change moves the lot together.
  readonly property int barMarginTop: AppearanceStore.barMarginTop
  readonly property int barMarginSide: AppearanceStore.barMarginSide

  // -- type --
  readonly property string fontMono: "JetBrains Mono"
  // spec §4: page titles only. Installed user-level and resolving via fontconfig.
  readonly property string fontDisplay: "Space Grotesk"

  // -- helpers --
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  readonly property url iconsDir: Qt.resolvedUrl("../Assets/icons")
}
