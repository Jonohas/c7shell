// Self-check for the pip geometry, which can be wrong silently (a 9-dot
// domino that renders 8 dots still "works"). The QML side has no test
// runner, so this loads the plain-JS source by hand and asserts on it.
//
//   node Modules/Bar/selfcheck.mjs
import assert from "node:assert/strict";
import fs from "node:fs";

function load(file, names) {
  const src = fs.readFileSync(new URL(file, import.meta.url), "utf8");
  const ns = {};
  const bind = names.map((n) => `__ns.${n} = ${n};`).join("\n");
  new Function("__ns", src + "\n" + bind)(ns);
  return ns;
}

const Pips = load("./Pips.js", ["layout", "window"]);

// -- faces and dominos: the dot count IS the workspace number --
for (let n = 1; n <= 12; n++) {
  const l = Pips.layout(n);
  assert.equal(l.dots.length, n, `layout(${n}) dot count`);
  assert.equal(l.divider, n >= 7, `layout(${n}) divider`);
  assert.equal(l.numeral, false, `layout(${n}) is drawn, not numeral`);
}
assert.equal(Pips.layout(6).dotSize, 3.5, "die faces use 3.5px dots");
assert.equal(Pips.layout(7).dotSize, 2.5, "domino halves use 2.5px dots");
assert.ok(Pips.layout(13).numeral, "13+ falls back to a numeral");
assert.equal(Pips.layout(13).dots.length, 0, "numeral tiles draw no dots");
assert.ok(Pips.layout(0).numeral, "0 is not a die face");

// -- every dot stays inside the tile and clear of its neighbours --
for (let n = 1; n <= 12; n++) {
  const l = Pips.layout(n);
  for (const [x, y] of l.dots) {
    assert.ok(x > 0.05 && x < 0.95 && y > 0.05 && y < 0.95, `layout(${n}) dot in bounds`);
  }
  const tile = 20;
  for (let i = 0; i < l.dots.length; i++) {
    for (let j = i + 1; j < l.dots.length; j++) {
      const dx = (l.dots[i][0] - l.dots[j][0]) * tile;
      const dy = (l.dots[i][1] - l.dots[j][1]) * tile;
      assert.ok(Math.hypot(dx, dy) >= l.dotSize, `layout(${n}) dots ${i},${j} overlap`);
    }
  }
}

// -- domino split: ceil over floor, top half first --
const nine = Pips.layout(9);
assert.equal(nine.dots.filter(([, y]) => y < 0.5).length, 5, "9 = 5 on top");
assert.equal(nine.dots.filter(([, y]) => y > 0.5).length, 4, "9 = 4 below");

// -- sliding window --
assert.deepEqual(Pips.window([1, 2, 3], 2, 5), [1, 2, 3], "under cap passes through");
assert.deepEqual(Pips.window([1, 2, 3, 4, 5, 6, 7], 4, 5), [2, 3, 4, 5, 6], "centered on focus");
assert.deepEqual(Pips.window([1, 2, 3, 4, 5, 6, 7], 1, 5), [1, 2, 3, 4, 5], "clamped at the left");
assert.deepEqual(Pips.window([1, 2, 3, 4, 5, 6, 7], 7, 5), [3, 4, 5, 6, 7], "clamped at the right");
assert.deepEqual(Pips.window([1, 2, 3, 4, 5, 6, 7], 99, 5), [1, 2, 3, 4, 5], "missing focus keeps the head");
assert.deepEqual(Pips.window([], 1, 5), [], "no workspaces, no tiles");

console.log("bar selfcheck: ok");
