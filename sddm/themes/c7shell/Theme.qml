pragma Singleton
import QtQuick

// The greeter's half of the shell's design tokens (quickshell/c7shell/Theme).
//
// It cannot import that one: sddm runs this QML as the `sddm` user, before any
// session exists, with no qs.Theme module on the import path. The COLOURS are
// no longer duplicated here either -- they come from PaletteStore.qml, which
// tools/gen-palette-qml.py compiles from the same palette.json the shell reads,
// which is how the greeter's crimson used to drift a shade from the shell's.
// Compiled rather than read at startup because plain QtQuick has no FileView
// and its XMLHttpRequest cannot open a local file without an environment
// variable sddm does not set: a login screen is the last place for a file read
// that can fail. tests/test-greeter.sh fails if the generated copy is stale.
//
// Only the defaults, never a user's accent: the greeter runs before any session
// exists and cannot read anybody's ~/.config/hypr/appearance.json.
//
// The geometry below is the greeter's own -- the mockup is a whole screen, and
// none of it means anything to the shell.
QtObject {
  id: root

  // -- scale ---------------------------------------------------------------
  // Every size below is written in the units of the 1120x630 mockup and
  // multiplied by this. Greeter.qml sets it once, from the primary screen:
  // the mockup is a whole screen, so a 1080p panel wants everything ~1.2x.
  property real s: 1
  // Rounded, because a half-pixel border is a grey smear rather than a hairline.
  function px(n) { return Math.round(n * root.s) }

  // -- color ---------------------------------------------------------------
  readonly property color bg: PaletteStore.palette.greeterBg
  readonly property color accent: PaletteStore.defaults.accent
  // Derived exactly as Theme.qml derives it -- same hue, 0.9x saturation,
  // +0.108 lightness -- rather than written out again. The two literals had
  // already drifted a shade apart.
  readonly property color accentSoft: Qt.hsla(root.accent.hslHue,
                                              root.accent.hslSaturation * 0.90,
                                              Math.min(1, root.accent.hslLightness + 0.108), 1)
  readonly property color text: PaletteStore.palette.text

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function ink(a) { return root.alpha(root.text, a) }
  function crimson(a) { return root.alpha(root.accent, a) }
  function white(a) { return Qt.rgba(1, 1, 1, a) }

  // glass: near-black translucent fill + a 1px hairline. sddm has no
  // compositor behind it to blur with, so the fill carries the whole effect
  // and sits a touch more opaque than the shell's.
  readonly property color panel: Qt.rgba(15 / 255, 15 / 255, 19 / 255, 0.72)
  readonly property color pillPanel: Qt.rgba(15 / 255, 15 / 255, 19 / 255, 0.80)
  readonly property color hairline: root.white(0.10)
  readonly property color hairlineSoft: root.white(0.09)
  readonly property color hover: root.white(0.08)
  readonly property color hoverRow: root.white(0.06)
  readonly property color field: root.white(0.05)
  readonly property color grid: root.white(0.022)

  readonly property color accentFill: root.crimson(0.14)
  readonly property color accentBorder: root.crimson(0.28)
  readonly property color focusBorder: root.crimson(0.50)
  readonly property color focusRing: root.crimson(0.12)
  readonly property color errorFill: root.crimson(0.09)
  readonly property color errorBorder: root.crimson(0.65)
  readonly property color battery: PaletteStore.palette.warning

  readonly property color shadow: Qt.rgba(0, 0, 0, 0.72)
  readonly property color shadowPill: Qt.rgba(0, 0, 0, 0.60)

  // -- geometry (mockup units) ---------------------------------------------
  readonly property int radiusCard: root.px(22)
  readonly property int radiusPanel: root.px(20)
  readonly property int radiusRow: root.px(12)
  readonly property int radiusSessionRow: root.px(11)
  readonly property int radiusField: root.px(13)
  readonly property int radiusBar: root.px(16)
  readonly property int radiusButton: root.px(10)

  readonly property int cardWidth: root.px(392)
  readonly property int userPanelWidth: root.px(250)
  readonly property int sessionPanelWidth: root.px(226)
  readonly property int panelGap: root.px(22)
  readonly property int fieldHeight: root.px(44)
  readonly property int avatarSize: root.px(76)
  readonly property int barItemHeight: root.px(30)
  readonly property int screenMargin: root.px(26)
  readonly property int screenMarginSide: root.px(32)

  // -- type ----------------------------------------------------------------
  readonly property string fontMono: "JetBrains Mono"
  // Avatar initials only, exactly as in the shell. Absent (it is an AUR font),
  // fontconfig substitutes another sans and the initials still read.
  readonly property string fontDisplay: "Space Grotesk"
  function fs(n) { return Math.max(7, Math.round(n * root.s)) }
}
