// Arithmetic for the calc provider. Hand-written tokenizer + recursive descent
// instead of eval()/Function(): the input is whatever the user typed into a
// keyboard-grabbing window, so it never reaches a JS interpreter.
//
// Grammar:
//   expr  := term (('+' | '-') term)*
//   term  := unary (('*' | '/' | '%') unary)*
//   unary := ('-' | '+') unary | power
//   power := atom ('^' unary)?          -- right associative
//   atom  := number | '(' expr ')'

function tokenize(src) {
  const tokens = [];
  let i = 0;

  while (i < src.length) {
    const c = src[i];

    if (c === " " || c === "\t") { i++; continue; }

    if ((c >= "0" && c <= "9") || c === ".") {
      let j = i;
      let dots = 0;
      while (j < src.length && ((src[j] >= "0" && src[j] <= "9") || src[j] === ".")) {
        if (src[j] === ".") dots++;
        j++;
      }
      const value = Number(src.slice(i, j));
      if (dots > 1 || !isFinite(value)) throw new Error("bad number");
      tokens.push({ k: "n", v: value });
      i = j;
      continue;
    }

    if ("+-*/^%()".indexOf(c) >= 0) { tokens.push({ k: c }); i++; continue; }

    throw new Error("unexpected '" + c + "'");
  }

  return tokens;
}

function evaluate(src) {
  const t = tokenize(src);
  let p = 0;

  function peek() { return p < t.length ? t[p].k : ""; }

  function atom() {
    if (peek() === "n") return t[p++].v;
    if (peek() === "(") {
      p++;
      const v = expr();
      if (peek() !== ")") throw new Error("missing ')'");
      p++;
      return v;
    }
    throw new Error("expected a number");
  }

  function power() {
    const base = atom();
    if (peek() === "^") { p++; return Math.pow(base, unary()); }
    return base;
  }

  function unary() {
    if (peek() === "-") { p++; return -unary(); }
    if (peek() === "+") { p++; return unary(); }
    return power();
  }

  function term() {
    let v = unary();
    while (peek() === "*" || peek() === "/" || peek() === "%") {
      const op = t[p++].k;
      const r = unary();
      if (r === 0 && op !== "*") throw new Error("divide by zero");
      v = op === "*" ? v * r : op === "/" ? v / r : v % r;
    }
    return v;
  }

  function expr() {
    let v = term();
    while (peek() === "+" || peek() === "-") {
      const op = t[p++].k;
      const r = term();
      v = op === "+" ? v + r : v - r;
    }
    return v;
  }

  if (t.length === 0) throw new Error("empty");
  const value = expr();
  if (p !== t.length) throw new Error("trailing input");
  if (!isFinite(value)) throw new Error("not a finite number");
  return value;
}

// 0.1 + 0.2 must read as 0.3, and 1/3 must not print 17 digits.
function format(value) {
  if (Number.isInteger(value)) return String(value);
  return String(Number(value.toPrecision(12)));
}

// { ok: true, value: "3" } | { ok: false, error: "missing ')'" }
function tryEval(src) {
  try {
    return { ok: true, value: format(evaluate(src)) };
  } catch (e) {
    return { ok: false, error: String(e.message || e) };
  }
}
