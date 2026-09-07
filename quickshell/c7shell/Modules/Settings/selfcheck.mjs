// Self-check for the accent picker's colour maths (Common/Hex.js). The QML
// side has no test runner, so this loads the plain-JS source by hand and
// asserts on it.
//
//   node Modules/Settings/selfcheck.mjs
//
// Every failure here is a silent one. A hue that round-trips a degree off
// walks the marker across the strip each time the picker reopens; a `format`
// that truncates instead of rounding writes a hex one step darker than the
// swatch the user clicked; and a `normalise` that lets a five-digit string
// through hands AppearanceStore a value its validator throws away for the
// palette default -- the picker appearing to do nothing at all.
import assert from "node:assert/strict";
import fs from "node:fs";

// The same by-hand loader Modules/Bar and Modules/Launcher/providers use: each
// selfcheck stands alone and is run with plain `node`, so the six lines are
// copied rather than shared.
function load(file, names) {
  const src = fs.readFileSync(new URL(file, import.meta.url), "utf8");
  const ns = {};
  const bind = names.map((n) => `__ns.${n} = ${n};`).join("\n");
  new Function("__ns", src + "\n" + bind)(ns);
  return ns;
}

const Hex = load("../../Common/Hex.js", ["fromHsv", "toHsv", "normalise", "format"]);

// -- what the store will accept -------------------------------------------
// The one shape AppearanceStore.accent validates against. Anything else is a
// value the shell will not paint.
const STORE = /^#[0-9a-f]{6}$/;

// -- normalise: what a person actually types ------------------------------
assert.equal(Hex.normalise("#e53a44"), "#e53a44", "the canonical form survives");
assert.equal(Hex.normalise("E53A44"), "#e53a44", "no hash, upper case");
assert.equal(Hex.normalise("  #E53A44  "), "#e53a44", "surrounding space");
assert.equal(Hex.normalise("#abc"), "#aabbcc", "shorthand doubles each digit");
assert.equal(Hex.normalise("abc"), "#aabbcc", "shorthand without the hash");
assert.equal(Hex.normalise("#000"), "#000000", "shorthand black");
assert.equal(Hex.normalise("#fff"), "#ffffff", "shorthand white");

for (const bad of ["", "#", "#12", "#12345", "#1234567", "#gggggg", "e53a4g",
                   "rgb(1,2,3)", "crimson", null, undefined, 0]) {
  assert.equal(Hex.normalise(bad), "", `rejects ${JSON.stringify(bad)}`);
}

// -- fromHsv: the sextant boundaries --------------------------------------
// Every one of these is a sector edge, which is where an off-by-one in the
// table shows up as a hue that jumps rather than sweeps.
assert.equal(Hex.fromHsv(0, 1, 1), "#ff0000", "0deg is red");
assert.equal(Hex.fromHsv(60, 1, 1), "#ffff00", "60deg is yellow");
assert.equal(Hex.fromHsv(120, 1, 1), "#00ff00", "120deg is green");
assert.equal(Hex.fromHsv(180, 1, 1), "#00ffff", "180deg is cyan");
assert.equal(Hex.fromHsv(240, 1, 1), "#0000ff", "240deg is blue");
assert.equal(Hex.fromHsv(300, 1, 1), "#ff00ff", "300deg is magenta");
assert.equal(Hex.fromHsv(360, 1, 1), "#ff0000", "360deg wraps back to red");
assert.equal(Hex.fromHsv(-60, 1, 1), "#ff00ff", "a negative hue wraps forward");
assert.equal(Hex.fromHsv(720 + 120, 1, 1), "#00ff00", "hues past a full turn wrap");

// The two axes of the SV square: value 0 is black at every hue, saturation 0
// is grey at every hue.
for (const h of [0, 37, 120, 250, 359]) {
  assert.equal(Hex.fromHsv(h, 1, 0), "#000000", `value 0 is black at ${h}deg`);
  assert.equal(Hex.fromHsv(h, 0, 1), "#ffffff", `saturation 0 is white at ${h}deg`);
  assert.equal(Hex.fromHsv(h, 0, 0.5), "#808080", `saturation 0 is grey at ${h}deg`);
}

// Out-of-range s/v are clamped, not wrapped: the marker sits on the edge of
// the square, and a drag a few px past it must not jump to the far corner.
assert.equal(Hex.fromHsv(0, 5, 5), "#ff0000", "s and v clamp at 1");
assert.equal(Hex.fromHsv(0, -5, -5), "#000000", "s and v clamp at 0");
assert.equal(Hex.fromHsv(NaN, 1, 1), "#ff0000", "a non-numeric hue is 0, not NaN");

// -- the picker's own round trip ------------------------------------------
// What the picker does on every open: read the accent in force, seed h/s/v
// off it, and write the same colour straight back.
const seeds = ["#e53a44", "#e24947", "#9964e5", "#1692c0", "#00a149",
               "#000000", "#ffffff", "#808080", "#0a0a0c", "#4ade80", "#e0b341"];
for (const seed of seeds) {
  const c = Hex.toHsv(seed);
  assert.match(Hex.fromHsv(c.h, c.s, c.v), STORE, `${seed} round-trips to a storable hex`);
  assert.equal(Hex.fromHsv(c.h, c.s, c.v), seed, `${seed} round-trips unchanged`);
}

// The whole hue strip, at the resolution the marker can actually address.
for (let h = 0; h < 360; h += 1) {
  const hex = Hex.fromHsv(h, 1, 1);
  assert.match(hex, STORE, `hue ${h} produces a storable hex`);
  // Within half a degree: the hex is 8 bits per channel, so the inverse of a
  // fully saturated hue lands on the nearest representable one, not the exact
  // one asked for.
  const back = Hex.toHsv(hex).h;
  const off = Math.min(Math.abs(back - h), 360 - Math.abs(back - h));
  assert.ok(off < 0.5, `hue ${h} round-trips to ${back}`);
}

// -- toHsv: the greys, and what it does with rubbish ----------------------
assert.equal(Hex.toHsv("#ffffff").s, 0, "white has no saturation");
assert.equal(Hex.toHsv("#ffffff").v, 1, "white is full value");
assert.equal(Hex.toHsv("#000000").v, 0, "black has no value");
// Grey's hue is meaningless rather than red -- the picker keeps its own when
// saturation is zero, and this is the value it must not trust.
assert.equal(Hex.toHsv("#808080").s, 0, "grey has no saturation");
assert.deepEqual(Hex.toHsv("nonsense"), { h: 0, s: 0, v: 0 }, "rubbish gives up as black");
assert.deepEqual(Hex.toHsv(""), { h: 0, s: 0, v: 0 }, "so does an empty string");

// Shorthand reaches toHsv through the same normalise, so #abc and #aabbcc are
// one colour and not two.
assert.deepEqual(Hex.toHsv("#abc"), Hex.toHsv("#aabbcc"), "shorthand is the long form");

// -- format: rounding, not truncation -------------------------------------
assert.equal(Hex.format(1, 1, 1), "#ffffff", "full channels do not lose a step");
assert.equal(Hex.format(0, 0, 0), "#000000", "empty channels stay empty");
assert.equal(Hex.format(0.5, 0.5, 0.5), "#808080", "half rounds up to 0x80");
assert.equal(Hex.format(2, -2, 0.5), "#ff0080", "channels clamp before rounding");

console.log("settings selfcheck: ok");
