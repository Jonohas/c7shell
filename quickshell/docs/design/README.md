# Handoff: Quickshell DE — crimson7 Hyprland shell

## Overview
A complete desktop-shell design for Hyprland implemented with Quickshell: topbar, command window (launcher), per-icon popovers (wifi / bluetooth / audio), calendar + notifications, settings app, power dropdown, keyboard-shortcut OSDs, and a screenshot/screen-recording overlay. Visual language derived from crimson7.io: crimson accent on near-black glass, mono-heavy operator typography, macOS/GNOME roundness with a Hyprland vibe.

## About the Design Files
The bundled \`Quickshell DE Mockups.dc.html\` is a **design reference created in HTML** — a static mockup canvas, not production code. The task is to **recreate these designs in Quickshell (QtQuick/QML)** on Hyprland, using layer-shell windows and the Quickshell service APIs. Open the HTML in a browser to see every screen; ids (1a, 1c, 1d…) below refer to the badges on the canvas.

## Fidelity
**High-fidelity.** Colors, spacing, radii, and typography are final and should be matched closely. Icons in the mocks are placeholder strokes — substitute a coherent icon set (e.g. Lucide/Phosphor line icons at 1.3–1.5px stroke).

## Design Tokens
Colors
- bg (desktop fallback): #0a0a0c · app canvas #0f0e10
- glass surface: rgba(15,15,19,.68–.82) + backdrop blur 24–26 + saturate 1.3
- surface raised (rows/cards on glass): rgba(255,255,255,.04–.07)
- hairline border: rgba(255,255,255,.07–.10) (1px)
- accent: #e53a44 · accent soft/text: #e5717a
- accent fill on glass: rgba(229,58,68,.13–.16), border rgba(229,58,68,.25–.35)
- text: #f0eff1 · secondary rgba(240,239,241,.55) · tertiary .35–.45 · disabled .28
- success dot: #4ade80
- alternate accents (appearance page, oklch, same L/C): oklch(0.62 0.19 25 / 300 / 230 / 150)

Typography (JetBrains Mono for ALL UI text; Space Grotesk 700 only for page titles)
- page title 15px/700 Space Grotesk
- row title 11.5–12.5px/600 mono · row sub 9.5–10px/400 mono
- bar modules 11–11.5px/500–700 mono · captions 9–10px mono
- lowercase labels everywhere except app names / menu items

Geometry
- radii: bar island 19 · large panels/windows 18–20 · rows/tiles 10–14 · chips 8–10 · workspace pips 7
- topbar: 38px tall, 10px top margin, 12px side margins
- popovers: 320–372px wide, padding 14–16, gap 10–14
- sliders: 5–6px track, radius 3, white 13px thumb, crimson fill + glow (0 0 12px rgba(229,58,68,.4))
- toggles: 30×17 pill, crimson when on
- shadows: panels 0 24px 80px rgba(0,0,0,.65) · bar 0 12px 40px rgba(0,0,0,.5)
- hyprland: rounding 19, gaps_out 12, blur size ~8 passes 3 (mock states "blur 24")

## Screens / Views (by canvas id)
### 1a Topbar (chosen direction: floating island)
Single 38px rounded island (r19) spanning the monitor minus 12px margins.
- Left: workspace pips — 20×20 r7 tiles showing dice-pip count per workspace (3.5px white dots; layouts 1=center, 2=diag, 3=diag+center, 4=corners, 5=corners+center). Focused = crimson bg + glow (0 0 10px rgba(229,58,68,.5)); occupied = rgba(255,255,255,.07) bg, .55 dots; empty = .04 bg, .22 dots. Then the **global menu**: app name 700 white, items (File, Edit, View, History, Help) 500 at .6 alpha, 3px 8px padding, r8 hover pill rgba(255,255,255,.1). Open dropdown: 180px glass menu, rows 10.5px mono with right-aligned shortcut, selected row solid crimson r8, 1px separators.
- Center: date+time pill (rgba(255,255,255,.05), r13): "tue aug 25" .75 + 1px divider + time 700 in #e5717a. Click → 1d.
- Right: tray pill (14px placeholder icons), status pill (wifi, bt, volume icons + battery 18×11 outline with crimson fill + %), then 28px circular power button (crimson tint bg, #e5717a power glyph) → 3a.
- Recording state (5b): center pill becomes solid crimson (rgba(229,58,68,.85) + glow): white dot, elapsed 02:14 700 white, divider, ■ stop, ⏸ pause. Everything else unchanged.

### 1c Command window
600px glass window (r20), centered, opened with super+space.
- Header: ">_" prompt in #e5717a, 14px input with 8×16 crimson block caret, "esc" kbd chip (bordered, r6).
- Provider chips: apps / actions / windows / calc / files — active solid crimson r9, inactive rgba(255,255,255,.05); right-aligned hint "tab ⇥ cycles".
- Results: rows r12, 32px r10 icon tile (2-letter monogram or glyph), title 12.5/600 + sub 10/400 ("app · web browser", "action · ~/.config/qs/scripts", "window · workspace ⚂ 3", "system · hyprlock"). Selected row: crimson tint bg + border + "↵" chip. Right meta: run / jump / ctrl+l.
- Footer: "↑↓ move · ↵ open · ctrl+↵ terminal · = calc inline", crimson square + "c7shell" right.

### 1d Calendar + notifications (clock popover)
360px glass panel: big clock 22px/700 (+dim seconds), date right in #e5717a. Month card (rgba(255,255,255,.04)): header "august 2026" + ‹ › ; weekday row 9.5px .35 (sa/su tinted crimson .5); 7-col grid, 10.5px/500 .75, off-month .25, today = crimson r8 pill 700 white. Notifications header "notifications N" (count crimson) + bordered "clear all" chip; rows r12: 28px monogram tile, app 11/600, time 9px .35 right, body 10px .55. Footer: "do not disturb" + toggle.

### 1e Wi-Fi popover (320px)
Header: "wi-fi" 600 + "wlan0" .35 + toggle. Connected card (crimson tint + border): wifi icon #e5717a, ssid 11.5/600, sub "connected · wpa3 · 10.7.0.21", right "-42dBm" #e5717a. Section label "other networks" 9.5 .35. Rows: wifi icon (arcs dimmed by signal), ssid 11/500 .8, lock glyph, dBm .35. Footer split: "⟳ rescan" | "network settings →" (crimson).

### 1f Bluetooth popover (320px)
Same skeleton. Connected devices as cards (first crimson-tinted): name 11.5/600, sub "connected · a2dp sink / hid", battery "▮ 80%" right. "nearby" label + spinner (8px arc). Rows with crimson "pair"; unknown MACs dimmed. Footer "⟳ scan" | "bluetooth settings →".

### 1g Audio popover (330px)
Card 1: output row (speaker icon, "output · WH-1000XM5", value) + slider; input row ("input · Blue Yeti") + softer slider (rgba(229,113,122,.7) fill). "devices": selectable rows r10, active = crimson tint + 6px crimson dot. "apps": per-app rows — 24px monogram tile, name 10/500, 4px mini slider, value; muted app at .45 opacity with ✕. Footer "sound settings →".

### 3a Power dropdown (232px, from power button)
Header: "red@c7-desk" 11/600 + "up 6h 12m" 9px .4, bottom hairline. Rows r10 (icon 13px, label 11/500, right hint): lock (super+l), logout, suspend, — separator — reboot, shutdown = crimson tint + border, 600, right hint "hold ↵" (hold-to-confirm).

### 4a/4b OSD pills
320px wide pill, r18, bottom-center, glass, shadow 0 20px 60px. Icon 17–18px + 6px track slider + value 12/600 (volume 68, brightness 45). Muted: crimson border, crimson icon, empty track, "mute" in #e5717a. Toggle events reuse the pill: mic muted (crimson border + icon, right hint super+m), layout "us → de", workspace N with crimson pip tile. One pill at a time, replace-in-place, hide after ~1.2s.

### 5a Screenshot overlay
Fullscreen dim rgba(4,4,6,.6). Selection: 1.5px #e53a44 rect, r4, faint crimson fill, 7px white corner handles with crimson border, "1680 × 920" badge top-right (glass chip). Hint top-left: "drag to select · space moves selection · esc cancels". Bottom-center toolbar (glass, r17, padding 6): shot|rec segmented (active solid crimson) · targets: region (active = crimson tint chip w/ icon), window, screen, all screens · divider · "⏱ 3s" · "copy" · capture button solid crimson with glow + ↵.

### 5b Record mode
Same toolbar, rec active: targets + mic chip (active, crimson mic glyph), "sys audio" (inactive .5), "60fps", "● start" crimson. Topbar = 1a with crimson recording island (see 1a). Finished toast (top-right glass card): striped thumb placeholder 52×32, filename 10.5/500, actions "open (crimson) · folder · delete".

### 2a/2b Settings app (790px window, tiles — NO close/min/max buttons)
Sidebar 212px, right hairline: search field (rgba(255,255,255,.05) r9), group labels 9px .3 (connectivity / system / shell), items 11px/500 .75 padding 7px 9px r9, active = solid crimson 600 white. Pages: wi-fi, network & vpn, bluetooth, appearance, displays, audio, power, notifications, topbar & widgets, keybinds.
- 2a Network & VPN: title 15/700 Space Grotesk + sub 10 .4; eth0 card with green dot + "details →"; "vpn tunnels" header + bordered "+ add tunnel" chip; tunnel cards (active = crimson tint, lock icon, "active 2h 14m · 10.100.0.4 · endpoint hq.crimson7.io:51820", toggle on; inactive dim with off toggle); dns card: chips 1.1.1.1 / 9.9.9.9 / "+ add", "route all traffic through active vpn" + toggle.
- 2b Appearance: theme preview cards ×3 (dark default selected w/ 2px crimson border, oled black, light), accent swatch row (crimson selected w/ white ring + 4 oklch alternates + "from wallpaper" toggle), sliders card: rounding 19px / gaps 12px / blur 24 + "window opacity on inactive" toggle, wallpaper card: current thumb (crimson radial) + striped "img" placeholder + "browse →".

## Interactions & Behavior
- Popovers: anchored to their bar module, scale+fade in ~150ms, dismiss on outside-click/esc. One open at a time.
- Command window: global toggle super+space; tab cycles providers; ↑↓ / ↵ / ctrl+↵; typing "=" switches to calc inline.
- OSD: replace-in-place, ~1.2s auto-hide, no stacking.
- Shutdown + capture destructive actions: hold-to-confirm (fill animation).
- Global menu: dbusmenu/appmenu registrar when app exports a menu; fallback = focused window title.
- Recording: island swap is the ONLY topbar change while recording.

## State & Data sources (Quickshell)
- workspaces/windows: Quickshell.Hyprland (focused, occupied, urgent) · clock: SystemClock
- notifications: Quickshell NotificationServer (shell IS the daemon) · tray: Quickshell.Services.SystemTray
- audio: Quickshell.Services.Pipewire (sinks, sources, per-app streams) · battery: UPower
- wifi: NetworkManager DBus (or nmcli subprocess v1) · bluetooth: BlueZ DBus (battery via org.bluez.Battery1)
- screenshot: grim + slurp-like own overlay, wl-copy · record: wf-recorder or gpu-screen-recorder
- settings app: separate QtQuick window (tiles, no CSD); appearance page writes theme singleton + hyprctl keywords; wallpaper via swww

## Suggested build order
1. Theme singleton + GlassPanel + topbar (workspaces, clock, battery)
2. Popovers: audio → wifi → bluetooth → calendar/notifications
3. Command window (apps provider first)
4. OSDs
5. Power dropdown + capture overlay
6. Settings app
7. Global menu via dbusmenu (biggest unknown — ship window-title fallback first)

## Packages
quickshell hyprland hyprlock swww grim wl-clipboard wf-recorder brightnessctl networkmanager bluez pipewire ttf-jetbrains-mono + Space Grotesk.

## Assets
No raster assets. Fonts: JetBrains Mono, Space Grotesk (Google Fonts). Icons: placeholder strokes in mocks — pick a line icon set. Wallpapers in mocks are CSS radial gradients (crimson glow on near-black) — any dark wallpaper works; "from wallpaper" accent option in 2b implies a matugen-style extraction later.


## Changes since first handoff (2026-08-26)
- **1h Battery icon states**: discharging (crimson fill), charging (green fill + white bolt overlay, green %), on-power-not-charging (grey fill + plug glyph), critical (crimson outline + crimson %). Same icon+% slot in the bar; fill color carries the state, glyph overlays the fill.
- **1i Network icon states**: wifi primary (arcs icon), LAN primary (ethernet/nodes glyph swaps into the SAME slot; popover 1e then leads with the eth0 card), no connectivity (crimson tint + ✕).
- **Quick-settings interaction rules** (topbar 1a):
  - Popovers are exclusive — clicking a quick-settings icon closes any open popover and opens the clicked one immediately.
  - Hover state on every quick-settings icon: rgba(255,255,255,.09) rounded pill (r8) behind the icon, 120ms fade; the power button hovers to rgba(229,58,68,.28). Active/open icon holds a crimson-tint pill rgba(229,58,68,.16).
  - The status cluster is now individual 24×22 r8 hit targets inside the pill (battery pill is 22px tall with 6px side padding).
- **Screenshare indicator** (1a): conditional crimson screen icon (rgba(229,58,68,.18) pill, #e5717a glyph) first in the quick-settings cluster, shown ONLY while a capture session is active; click reveals which app is sharing + stop.
- **6a Arch update module**: tray badge with update count (crimson tint when a kernel update is pending, dim grey otherwise, hidden at 0). Dropdown: header "updates N · checked Xm ago · ⟳", kernel warning card (old → new, reboot note), collapsible source groups pacman/aur/flatpak with counts and package version diffs, footer "update all" (crimson) + "terminal".
- **Turn 7 update wizard** (tiling window, no CSD; opened by "update all"): step indicator 1-2-3 top-right.
  - 7a review & approve: dry-run first; routine bumps collapsed as auto-approved; decision cards with crimson checkboxes for kernel, package replacement (jack2 → pipewire-jack), PGP key import, changed AUR PKGBUILD ("view diff"). Unchecked = skipped, not blocked. The run itself NEVER prompts.
  - 7b running: progress bar, dark log tail (rgba(0,0,0,.35) card, 9.5px mono), AUR build line highlighted; "hide" (continues in background, bar icon shows progress) + crimson-bordered "abort".
  - 7c finish: duration + log path; pacnew cards with keep mine / take new / merge… actions (recommended action solid crimson; hint "default untouched → safe to take new"); kernel reboot prompt card (reboot now / later); unresolved pacnews stay listed in settings → system.
- **Turn 8 screenshare picker** (8a): custom xdg-desktop-portal dialog, centered over dimmed+blurred desktop. Requesting app header ("Zoom wants to share your screen"), screens/windows/region segmented tabs, monitor cards with live-thumbnail placeholders + resolution/refresh labels (selected = 2px crimson border + glow + crimson check), toggles "hide notifications while sharing" (default on) + "share audio", footer cancel / "share DP-1 →" (crimson).
- **5b recording topbar** finalized earlier: identical to 1a except the center date/time island becomes solid crimson with elapsed timer + ■ stop + ⏸ pause.
- Scrapped: 1b flush topbar (hidden, still in HTML source).

## Files
- \`Quickshell DE Mockups.dc.html\` — the full mockup canvas (open in a browser). Turn 8 = screenshare picker, 7 = update wizard, 6 = arch updates, 5 = capture, 4 = OSDs, 3 = power, 2 = settings, 1 = topbar/launcher/popovers/icon-states. Hidden option 1b (scrapped flush bar) remains in source.
