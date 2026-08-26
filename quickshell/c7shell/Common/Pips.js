// Pip geometry for WorkspacePips: 1–6 are die faces, 7–12 are scatter faces
// (an even hexagon ring of six with the remainder ringed in the middle),
// 13+ falls back to a numeral.
// Pure functions on the unit square so selfcheck.mjs can assert on them.

// Dot centers for a die face of value n on the unit square. Quarter-grid
// positions: the edge margins equal the dot gaps, so the face reads evenly
// spaced instead of clustered at the center.
function face(n) {
  const lo = 0.25, mid = 0.50, hi = 0.75
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

// k dot centers evenly angled on a circle of radius r around the tile center.
function ring(k, r, phase) {
  const out = []
  for (let i = 0; i < k; i++) {
    const a = phase + (i * 2 * Math.PI) / k
    out.push([0.5 + r * Math.cos(a), 0.5 + r * Math.sin(a)])
  }
  return out
}

// Scatter face for 7–12: a hexagon ring of six, remainder in the middle —
// a lone center dot for 7, a small ring for 8+. The inner ring is offset a
// half step against the outer so the two never line up on one radius.
function scatter(n) {
  const outer = ring(6, 0.32, -Math.PI / 2)
  const inner = n - 6
  if (inner === 1) return outer.concat([[0.5, 0.5]])
  return outer.concat(ring(inner, 0.16, -Math.PI / 2 + Math.PI / inner))
}

// { dots: [[x,y]…] in tile units, dotSize: px, divider: bool, numeral: bool }
function layout(n) {
  if (n >= 1 && n <= 6)
    return { dots: face(n), dotSize: 3.5, divider: false, numeral: false }
  if (n >= 7 && n <= 12)
    return { dots: scatter(n), dotSize: 2.5, divider: false, numeral: false }
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
