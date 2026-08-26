# gambleland conventions (read before writing any QML here)

## Verified environment quirks — violating these costs a debug cycle
- Hyprland uses a Lua dispatch dialect: `Hyprland.dispatch('hl.dsp.focus({ workspace = N })')`,
  `hl.dsp.window.move({...})`. Stock dispatcher strings ("workspace 3") FAIL. Lua API stubs:
  /usr/share/hypr/stubs/hl.meta.lua.
- Blur invariant (conf/rules.lua, ignore_alpha = 0.7): every gambleland glass surface alpha ≥ 0.7
  (bar .78, panels .80); every gambleland shadow peak alpha ≤ .65 (barShadowColor .5,
  panelShadowColor .65). New surfaces/shadows must respect this or blur breaks.
- `font.pixelSize` is int — 11.5 is a load error; round it.
- Tray/dbus menus need `//@ pragma UseQApplication` (already in shell.qml).
- Shadows/glows: use `RectangularShadow` (QtQuick.Effects, Qt ≥ 6.9). NEVER MultiEffect
  shadows — MultiEffect paints its source (caused a hidden white-slab bug).
- Repeater rule: never bind a filtered/rebuilt JS array of an ObjectModel as `model` —
  segfaults. Bind the ObjectModel or a constant; filter in delegates via `visible`.
- Pipewire: any node whose .volume/.muted/.audio you read must sit in a `PwObjectTracker`.
- Icons: SVGs in Assets/icons painted #ffffff (no currentColor — Qt SVG lacks it); tint at
  runtime via Common/Icon.qml (`Icon { name; tint; size }`). New icons: lucide, same treatment.
- PopupWindow focus grabs must be deferred a frame after mapping (see _archive/PopupPanel.qml).

## Architecture rules
- Views consume services only: zero Process/DBus in view files. Wrap logic in Services/ singletons.
- One component per file, < 300 LoC. `import qs.<Dir>` module imports; singletons =
  `pragma Singleton` + `Singleton {}` (no qmldir).
- Every color/radius/font from Theme (qs.Theme). Pills: Theme.pillHeight/pillRadius.
  Shadows: Theme.barShadowColor/panelShadowColor. Glass: GlassPanel (Common/) —
  Theme.glassAlphaPanel for panels. Fonts: Theme.fontMono everywhere;
  Theme.fontDisplay (Space Grotesk, installed user-level) for settings page titles only.
- Lowercase labels everywhere except app names / menu items.
- _archive/ is reference-only: mine it for working service logic (Pipewire node filtering,
  nmcli handling, BlueZ, notification daemon), never import it.

## Cross-module contracts
- PopoverManager (Services/): `current` (string, "" = none), `anchorItem`,
  `toggle(name, item)`, `close()`. One popover at a time.
- SettingsService (Services/): `open(page)` + `openRequested(string page)` signal —
  popover footers call SettingsService.open("wifi"); SP6 connects the window.
- RecordingService (Services/): interface FINAL (`active/paused/elapsed/elapsedText/
  start()/stop()/togglePause()`); SP5 replaces stub internals with wf-recorder.
- ClockPill has `signal clicked()` (calendar popover), PowerButton has `signal clicked()`
  (power dropdown) — wired at integration.

## For worktree authoring agents (parallel phase)
- Do NOT touch: Modules/Bar/Bar.qml, shell.qml, Theme/Theme.qml, anything in ~/.config/hypr.
- Do NOT run `qs`, `hyprctl` state changes, or any live-session command — the live shell
  belongs to the integration session. Static discipline only (careful transcription,
  qmllint if useful, node-free logic review).
- Deliver an INTEGRATION.md at your worktree root: exact wiring snippets (imports +
  instantiations for shell.qml/Bar.qml), Theme token additions you need (name: value,
  justified against the spec), hypr binds/rules needed, icons added, runtime verification
  checklist for the integrator (commands + expected pixels/behavior per DoD line).
- Commit rules: imperative what+why; NEVER Co-Authored-By; NEVER mention AI/models/sessions.

## Verification method (integration phase)
Restart check: `qs kill; timeout 6 qs 2>&1 | tee log; grep -ciE "warn|error"` → 0, then `qs -d`.
Pixel probes via grim + magick against a killed-shell baseline. Screenshot per panel vs mockup
(docs/design/README.md is authoritative for tokens/geometry).
