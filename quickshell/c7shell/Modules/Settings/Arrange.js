// Drop geometry for ArrangeCanvas, in Hyprland's logical pixels. Pure
// functions on plain {x, y, w, h} rects so selfcheck.mjs can assert on them.

// Length two spans share; zero or less means they do not meet.
function span(a, al, b, bl) {
  return Math.min(a + al, b + bl) - Math.max(a, b)
}

// One logical px of slack: a fractional scale leaves sizes like 1365.33, and
// the rounded neighbour must still count as butting, not overlapping.
function overlaps(r, o) {
  return span(r.x, r.w, o.x, o.w) > 1 && span(r.y, r.h, o.y, o.h) > 1
}

// Slide a screen of length `len` along a neighbour's edge at `o`..`o+olen`:
// keep a quarter of the shorter edge shared so the cursor can always cross,
// and pull flush to either end when within `tol`.
function slide(v, len, o, olen, tol) {
  const min = Math.min(len, olen) / 4
  const c = Math.max(o - len + min, Math.min(o + olen - min, v))
  for (const f of [o, o + olen - len])
    if (Math.abs(f - c) <= tol) return f
  return c
}

// Where a screen of size `me` dropped at (lx, ly) lands: the nearest spot that
// touches some neighbour on a side and overlaps none. A free drop would let it
// float off with a gap the cursor cannot cross, or sit on top of another
// screen. null when every side of every neighbour is taken.
function place(me, others, lx, ly, tol) {
  if (others.length === 0) return { x: 0, y: 0 }
  let best = null, bd = Infinity
  for (const o of others) {
    const sx = slide(lx, me.w, o.x, o.w, tol)
    const sy = slide(ly, me.h, o.y, o.h, tol)
    const sides = [
      { x: o.x + o.w, y: sy }, { x: o.x - me.w, y: sy },
      { x: sx, y: o.y + o.h }, { x: sx, y: o.y - me.h }
    ]
    for (const c of sides) {
      const r = { x: Math.round(c.x), y: Math.round(c.y), w: me.w, h: me.h }
      if (others.some(q => overlaps(r, q))) continue
      const d = Math.hypot(r.x - lx, r.y - ly)
      if (d < bd) { bd = d; best = r }
    }
  }
  return best && { x: best.x, y: best.y }
}

// Shift every top-left so the desk starts at 0,0. Dragging the left screen to
// the right otherwise leaves the layout at negative coordinates, which
// XWayland clients position badly.
function normalise(rects) {
  const x0 = Math.min(...rects.map(r => r.x))
  const y0 = Math.min(...rects.map(r => r.y))
  return rects.map(r => Object.assign({}, r, { x: r.x - x0, y: r.y - y0 }))
}
