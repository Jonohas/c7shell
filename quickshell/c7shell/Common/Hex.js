// Hex ↔ HSV for the accent picker (Modules/Settings/AccentPicker.qml).
//
// Plain JS rather than Qt.hsva/Qt.colorEqual for one reason: this is the only
// arithmetic in the picker, and a hue that comes back a degree off, or a hex
// field that quietly rejects `#ABC`, is exactly the kind of wrong that looks
// fine on screen. Pure functions, so Modules/Settings/selfcheck.mjs can assert
// on them without a QML engine.
//
// The hex strings written here reach AppearanceStore.values.accent, whose
// validator is /^#[0-9a-fA-F]{6}$/ -- so `format` produces that shape and
// nothing else, and `normalise` returns "" rather than a near-miss the store
// would silently swap for the palette default.

// H in 0..360 (360 wraps to 0), S and V in 0..1.
function clampHsv(h, s, v) {
  const wrap = ((Number(h) % 360) + 360) % 360
  return {
    h: isNaN(wrap) ? 0 : wrap,
    s: clamp01(s),
    v: clamp01(v),
  }
}

function clamp01(n) {
  const x = Number(n)
  return isNaN(x) ? 0 : Math.max(0, Math.min(1, x))
}

// One channel byte as two lower-case hex digits. Rounded, not truncated:
// truncation loses a whole step off every channel and turns #ffffff into
// #fefefe.
function byte(x) {
  return Math.round(clamp01(x) * 255).toString(16).padStart(2, "0")
}

function format(r, g, b) {
  return `#${byte(r)}${byte(g)}${byte(b)}`
}

// The usual sextant walk. Returns `#rrggbb`.
function fromHsv(h, s, v) {
  const c = clampHsv(h, s, v)
  const sector = c.h / 60
  const chroma = c.v * c.s
  // The second-largest component: how far into the sector we are, mirrored on
  // odd sectors so the ramp reverses instead of stepping at every boundary.
  const mid = chroma * (1 - Math.abs((sector % 2) - 1))
  const lo = c.v - chroma
  const table = [
    [chroma, mid, 0], [mid, chroma, 0], [0, chroma, mid],
    [0, mid, chroma], [mid, 0, chroma], [chroma, 0, mid],
  ]
  // 359.9999/60 floors to 5; a hue of exactly 360 was already wrapped to 0.
  const [r, g, b] = table[Math.min(5, Math.floor(sector))]
  return format(r + lo, g + lo, b + lo)
}

// Accepts what a person types: `#e53a44`, `E53A44`, ` #abc `, `abc`. Returns
// the six-digit lower-case form, or "" for anything else -- an empty return is
// the caller's cue to leave the accent alone rather than write a fallback.
function normalise(text) {
  const raw = String(text ?? "").trim().replace(/^#/, "")
  if (/^[0-9a-fA-F]{3}$/.test(raw)) {
    // Shorthand doubles each digit: #abc is #aabbcc, not #a0b0c0.
    return `#${raw.split("").map(d => d + d).join("").toLowerCase()}`
  }
  if (/^[0-9a-fA-F]{6}$/.test(raw)) return `#${raw.toLowerCase()}`
  return ""
}

// Inverse of fromHsv, for seeding the picker off whatever accent is in force.
// An invalid hex gives up as black rather than throwing: the picker opens on
// something, and the store's own validator has already decided what the shell
// is actually painting.
function toHsv(hex) {
  const clean = normalise(hex)
  if (clean === "") return { h: 0, s: 0, v: 0 }
  const [r, g, b] = [1, 3, 5].map(i => parseInt(clean.slice(i, i + 2), 16) / 255)
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const chroma = max - min
  // Grey has no hue at all. Reporting 0 (red) would swing the picker's hue
  // strip to one end for every neutral, so the caller keeps its own hue when
  // saturation is zero.
  let h = 0
  if (chroma > 0) {
    if (max === r) h = 60 * (((g - b) / chroma) % 6)
    else if (max === g) h = 60 * ((b - r) / chroma + 2)
    else h = 60 * ((r - g) / chroma + 4)
  }
  return { h: ((h % 360) + 360) % 360, s: max === 0 ? 0 : chroma / max, v: max }
}
