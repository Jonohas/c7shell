// Self-check for the two pieces of launcher logic that can be wrong silently:
// the arithmetic parser and the fuzzy ranker. The QML side has no test runner,
// so this loads the plain-JS sources by hand and asserts on them.
//
//   node Modules/Launcher/providers/selfcheck.mjs
import assert from "node:assert/strict";
import fs from "node:fs";

function load(file, names) {
  const src = fs.readFileSync(new URL(file, import.meta.url), "utf8");
  const ns = {};
  const bind = names.map((n) => `__ns.${n} = ${n};`).join("\n");
  new Function("__ns", src + "\n" + bind)(ns);
  return ns;
}

const Calc = load("./Calc.js", ["evaluate", "format", "tryEval"]);
const Search = load("./Search.js", ["score", "rank", "initials"]);

// -- arithmetic --
assert.equal(Calc.evaluate("1+2*3"), 7, "precedence");
assert.equal(Calc.evaluate("(1+2)*3"), 9, "parens");
assert.equal(Calc.evaluate("2^3^2"), 512, "^ is right associative");
assert.equal(Calc.evaluate("-2^2"), -4, "unary minus binds looser than ^");
assert.equal(Calc.evaluate("10 % 3"), 1, "modulo");
assert.equal(Calc.evaluate("  8 / 4  "), 2, "surrounding space ignored");
assert.equal(Calc.evaluate("-(4/2)"), -2, "unary on a group");
assert.equal(Calc.format(0.1 + 0.2), "0.3", "float fuzz trimmed");
assert.equal(Calc.format(4), "4", "integers stay bare");

for (const bad of ["1/0", "1+", "(1", "1)", "2..5", "1 2", "", "1+alert(1)", "0x10"]) {
  assert.equal(Calc.tryEval(bad).ok, false, `must reject: ${bad}`);
}
assert.equal(Calc.tryEval("3*7").value, "21");

// -- fuzzy --
assert.equal(Search.score("zz", "Firefox"), -1, "no match is -1");
assert.ok(Search.score("ff", "Firefox") > Search.score("ff", "buffer overflow"),
  "word-start hits outrank scattered ones");
assert.ok(Search.score("fire", "Firefox") > Search.score("fox", "Firefox"),
  "prefix outranks a late run");
assert.equal(Search.score("", "anything"), 0, "empty query matches everything");

const apps = ["Firefox", "Files (Nautilus)", "Kitty"];
assert.deepEqual(Search.rank("", apps, (x) => x), apps, "empty query keeps input order");
assert.equal(Search.rank("fi", apps, (x) => x)[0], "Firefox");
assert.equal(Search.rank("nau", apps, (x) => x).length, 1, "misses are dropped");
assert.equal(Search.rank("i", apps, (x) => x, 2).length, 2, "limit honoured");

assert.equal(Search.initials("Firefox"), "fi");
assert.equal(Search.initials("Files (Nautilus)"), "fn");
assert.equal(Search.initials("firewall-reload"), "fr");
assert.equal(Search.initials("~/.config/qs/scripts"), "cq");
assert.equal(Search.initials("   "), "??", "no crash on junk");

console.log("launcher selfcheck: ok");
