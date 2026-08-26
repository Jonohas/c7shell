// Pip geometry for WorkspacePips: 1–6 are die faces, 7–12 are dominos
// (ceil(n/2) over floor(n/2) mini-faces), 13+ falls back to a numeral.
// Pure functions on the unit square so selfcheck.mjs can assert on them.

// Dot centers for a die face of value n on the unit square.
function face(n) {
  const lo = 0.30, mid = 0.50, hi = 0.70
  switch (n) {
    case 1: return [[mid, mid]]
    case 2: return [[lo, lo], [hi, hi]]
    case 3: return [[lo, lo], [mid, mid], [hi, hi]]
    case 4: return [[lo, lo], [hi, lo], [lo, hi], [hi, hi]]
    case 5: return [[lo, lo], [hi, lo], [mid, mid], [lo, hi], [hi, hi]]
    case 6: return [[lo, lo], [lo, mid], [lo, hi], [hi, lo], [hi, mid], [hi, hi]]
    default: return []
  }
}

// Dot centers for one domino half: x spans the full tile width, y spans the
// half (0..1, rescaled by the caller). Wider x steps than face() because the
// half is 20×10 — three columns fit, three rows do not.
function halfFace(n) {
  const lo = 0.25, mid = 0.50, hi = 0.75
  const yLo = 0.30, yMid = 0.50, yHi = 0.70
  switch (n) {
    case 1: return [[mid, yMid]]
    case 2: return [[lo, yMid], [hi, yMid]]
    case 3: return [[lo, yMid], [mid, yMid], [hi, yMid]]
    case 4: return [[lo, yLo], [hi, yLo], [lo, yHi], [hi, yHi]]
    case 5: return [[lo, yLo], [hi, yLo], [mid, yMid], [lo, yHi], [hi, yHi]]
    case 6: return [[lo, yLo], [mid, yLo], [hi, yLo], [lo, yHi], [mid, yHi], [hi, yHi]]
    default: return []
  }
}

// { dots: [[x,y]…] in tile units, dotSize: px, divider: bool, numeral: bool }
function layout(n) {
  if (n >= 1 && n <= 6)
    return { dots: face(n), dotSize: 3.5, divider: false, numeral: false }
  if (n >= 7 && n <= 12) {
    const top = halfFace(Math.ceil(n / 2)).map(p => [p[0], p[1] * 0.5])
    const bottom = halfFace(Math.floor(n / 2)).map(p => [p[0], 0.5 + p[1] * 0.5])
    return { dots: top.concat(bottom), dotSize: 2.5, divider: true, numeral: false }
  }
  return { dots: [], dotSize: 0, divider: false, numeral: true }
}

// Sorted ids → the ≤cap slice that keeps focusedId visible (centered,
// clamped at the ends; head slice if focusedId is not in ids).
function window(ids, focusedId, cap) {
  if (ids.length <= cap) return ids
  let idx = ids.indexOf(focusedId)
  if (idx < 0) idx = 0
  const start = Math.max(0, Math.min(idx - Math.floor(cap / 2), ids.length - cap))
  return ids.slice(start, start + cap)
}
