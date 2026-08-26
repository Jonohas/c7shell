// Fuzzy matching shared by the launcher providers. No .pragma library: the
// functions are stateless, and leaving the file plain JS keeps it loadable by
// selfcheck.mjs.

// Subsequence match. Returns a score (higher is better) or -1 for no match.
// Bonuses go to prefix hits, word-start hits and runs of adjacent characters,
// so "ff" ranks Firefox above "buffer overflow notes".
function score(needle, haystack) {
  const h = String(haystack).toLowerCase();
  const n = String(needle).toLowerCase();
  if (n === "") return 0;

  let at = 0;
  let total = 0;
  let streak = 0;

  for (let i = 0; i < n.length; i++) {
    const c = n[i];
    if (c === " ") continue;
    const found = h.indexOf(c, at);
    if (found < 0) return -1;

    if (found === 0) total += 12;
    else if (" -_./:".indexOf(h[found - 1]) >= 0) total += 8;

    streak = found === at ? streak + 1 : 0;
    total += 4 + streak * 2;
    at = found + 1;
  }

  // Mild preference for shorter haystacks so exact-ish names beat long paths.
  return total - Math.min(h.length, 60) * 0.1;
}

// Score every item, drop the misses, best first, capped. `textOf` builds the
// haystack for one item.
function rank(query, items, textOf, limit) {
  const scored = [];
  for (let i = 0; i < items.length; i++) {
    const s = score(query, textOf(items[i]));
    if (s >= 0) scored.push({ s: s, i: i, v: items[i] });
  }
  // Ties keep input order, so an already-sorted list stays sorted when the
  // query is empty.
  scored.sort(function (a, b) { return b.s - a.s || a.i - b.i; });
  return scored.slice(0, limit || 40).map(function (e) { return e.v; });
}

// Move the first item `pick` accepts to the front, leaving the rest in order.
// A hard hoist rather than a score bonus: "first hit" that depends on out-
// scoring whatever the machine happens to have installed is not a guarantee.
function pinFirst(items, pick) {
  const at = items.findIndex(pick);
  if (at <= 0) return items;
  const out = items.slice();
  out.unshift(out.splice(at, 1)[0]);
  return out;
}

// Two-letter monogram for the result tile: initials of the first two words,
// or the first two characters of a single word. "Files (Nautilus)" -> "fn".
function initials(text) {
  const words = String(text).split(/[\s\-_./()[\]]+/).filter(function (w) {
    return /[a-z0-9]/i.test(w);
  });
  if (words.length === 0) return "??";
  if (words.length === 1) return words[0].slice(0, 2).toLowerCase();
  return (words[0][0] + words[1][0]).toLowerCase();
}
