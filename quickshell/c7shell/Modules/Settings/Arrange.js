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
// and pull flush to either end, or centred on the neighbour, when within `tol`.
function slide(v, len, o, olen, tol) {
  const min = Math.min(len, olen) / 4
  const c = Math.max(o - len + min, Math.min(o + olen - min, v))
  let best = c, bd = tol
  for (const f of [o, o + olen - len, o + (olen - len) / 2]) {
    if (Math.abs(f - c) <= bd) { bd = Math.abs(f - c); best = f }
  }
  return best
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

// Where a drop lands once the snap setting has its say. With snap on, a
// touching spot within `reach` wins; otherwise the exact drop spot stands as
// long as it overlaps nothing. A drop onto a screen falls back to the touching
// spot with snap on, and is refused (null) with it off.
function land(me, others, lx, ly, tol, reach, snap) {
  const free = { x: Math.round(lx), y: Math.round(ly) }
  const clear = !others.some(o => overlaps({ x: free.x, y: free.y, w: me.w, h: me.h }, o))
  if (!snap) return clear ? free : null
  const p = place(me, others, lx, ly, tol)
  if (p && (!clear || Math.hypot(p.x - lx, p.y - ly) <= reach)) return p
  return clear ? free : null
}

// The alignment lines for `r` against its neighbours: wherever r's start edge,
// centre or end edge lines up (within the same 1px slack as overlaps) with one
// of a neighbour's, on either axis. Each line runs from r to that neighbour.
// r's start against a neighbour's end is skipped: that is the seam two
// touching screens share, and it lines up on every snapped drop.
// {vertical, at, from, to, centre}, in logical px.
function guides(r, others) {
  const out = [], seen = {}
  for (const o of others) {
    for (const [vertical, a, al, b, bl, c, cl] of [
      [true, r.x, r.w, o.x, o.w, Math.min(r.y, o.y), Math.max(r.y + r.h, o.y + o.h)],
      [false, r.y, r.h, o.y, o.h, Math.min(r.x, o.x), Math.max(r.x + r.w, o.x + o.w)]
    ]) {
      for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) {
        if (i + j === 2 && i !== j) continue
        const at = b + bl * j / 2
        if (Math.abs(a + al * i / 2 - at) > 1) continue
        const key = `${vertical}:${Math.round(at)}:${c}:${cl}`
        if (seen[key]) continue
        seen[key] = true
        out.push({ vertical: vertical, at: at, from: c, to: cl, centre: i === 1 })
      }
    }
  }
  return out
}

// Shift every top-left so the desk starts at 0,0. Dragging the left screen to
// the right otherwise leaves the layout at negative coordinates, which
// XWayland clients position badly.
function normalise(rects) {
  const x0 = Math.min(...rects.map(r => r.x))
  const y0 = Math.min(...rects.map(r => r.y))
  return rects.map(r => Object.assign({}, r, { x: r.x - x0, y: r.y - y0 }))
}
