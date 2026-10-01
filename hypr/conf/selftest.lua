-- Self-check for the two pure modules the monitor config depends on.
-- Run: lua conf/selftest.lua   (from ~/.config/hypr)
-- These parse a hand-editable file that then configures the compositor, so
-- "corrupt input yields the fallback" is the property worth asserting.

package.path = "./?.lua;" .. package.path
local json = require("conf/json")
local d = require("conf/displays")

-- json.decode
assert(json.decode('{"a":1}').a == 1)
assert(json.decode('  {"a" : "x\\"y" } ').a == 'x"y')
assert(json.decode('{"a":{"b":[1,2,{"c":true}]}}').a.b[3].c == true)
assert(json.decode('{"a":-1.5e2}').a == -150)
assert(json.decode('{"a":null,"b":2}').a == nil)
assert(json.decode('{"a":null,"b":2}').b == 2)
assert(json.decode('[]')[1] == nil)
assert(json.decode('{"p":"/home/x/a,b{c}.png"}').p == "/home/x/a,b{c}.png")
-- malformed -> nil, never a half-parsed table
for _, bad in ipairs({ '', '{', '{"a"}', '{"a":}', '{"a":1,}', '{"a":1} x',
                       '{"a":"unterminated', 'nope', '{"a":01x}' }) do
    assert(json.decode(bad) == nil, "should not parse: " .. bad)
end
-- decode_flat keeps appearance.lua's contract: never nil, scalars only
assert(next(json.decode_flat(nil)) == nil)
assert(next(json.decode_flat('{oops')) == nil)
local flat = json.decode_flat('{"theme":"dark","rounding":19,"on":true,"nested":{"x":1}}')
assert(flat.theme == "dark" and flat.rounding == 19 and flat.on == true)
assert(flat.nested == nil)

-- signature is order independent and description based
assert(d.signature({ "b", "a" }) == d.signature({ "a", "b" }))
assert(d.signature({ "a", "b" }) == "a|b")
assert(d.signature({ "a" }) ~= d.signature({ "a", "b" }))  -- lid shut is its own desk

-- validators: whitelist, not sanity check
assert(d.position("1000x1440") == "1000x1440")
assert(d.position("-3440x0") == "-3440x0")
for _, bad in ipairs({ "auto", "0x0 ", "1e9x0", "999999x0", "0x0;disabled=true", 5 }) do
    assert(d.position(bad) == nil, "position should reject: " .. tostring(bad))
end
assert(d.scale(2) == 2)
assert(d.scale(1.6) == 1.6)
for _, bad in ipairs({ 0, 99, -1, "2", 0 / 0 }) do
    assert(d.scale(bad) == nil, "scale should reject: " .. tostring(bad))
end
local modes = { { width = 2880, height = 1920, refresh_rate = 120.0 },
                { width = 3440, height = 1440, refresh_rate = 99.992 } }
assert(d.mode("2880x1920@120.00", modes) == "2880x1920@120.00")
assert(d.mode("3440x1440@99.99", modes) == "3440x1440@99.99")   -- ipc rounds to 2dp
assert(d.mode("3440x1440@144", modes) == nil)                    -- not offered
assert(d.mode("preferred", modes) == nil)
assert(d.mode("2880x1920@120.00", nil) == nil)                   -- nothing to check against

-- encode: enough JSON for the state file conf/monitors.lua writes, and nothing
-- more. Round-tripped through the decoder above rather than compared as text,
-- because key order in a lua table is not the property worth asserting.
assert(d.encode(nil) == "null")
assert(d.encode(true) == "true")
assert(d.encode(1) == "1")
assert(d.encode(1.5) == "1.5")
assert(d.encode(0 / 0) == "null")       -- NaN is not JSON
assert(d.encode("a") == '"a"')
assert(d.encode('a"b\\c') == '"a\\"b\\\\c"')
assert(d.encode("a\nb") == '"a\\nb"')
assert(d.encode({}) == "[]")            -- ambiguous; the state doc has no empty objects
assert(d.encode({ 1, 2 }) == "[1,2]")
-- string keys are sorted, so an unchanged layout writes a byte-identical file
-- and a watcher does not see a change that is not one
assert(d.encode({ b = 1, a = 2 }) == '{"a":2,"b":1}')
local round = json.decode(d.encode({
  setup = "BOE x|LG x", screens = { "BOE x", "LG x" }, parked = {},
}))
assert(round.setup == "BOE x|LG x" and round.screens[2] == "LG x")

-- write_state round-trips through a real file and reports failure rather than
-- raising: a settings page that cannot show its picker beats a config reload
-- that errors out.
local tmp = os.tmpname()
assert(d.write_state({ setup = "x", parked = { "Dell y" } }, tmp) == true)
assert(json.decode(json.read_file(tmp)).setup == "x")
assert(d.parked(tmp)[1] == "Dell y")
os.remove(tmp)
assert(d.write_state({ setup = "x" }, "/proc/nonexistent/nope.json") == false)
assert(#d.parked("/proc/nonexistent/nope.json") == 0)
local tmp2 = os.tmpname()
assert(d.write_state({ panel = "eDP-1" }, tmp2))
assert(d.panel(tmp2) == "eDP-1")
assert(d.write_state({ panel = 'eDP-1",x' }, tmp2))
assert(d.panel(tmp2) == nil, "a connector name is only ever [%w-]")
os.remove(tmp2)
assert(d.panel("/proc/nonexistent/nope.json") == nil)

assert(d.bitdepth(10) == 10 and d.bitdepth(8) == 8)
for _, bad in ipairs({ 12, "10", 0, true }) do
    assert(d.bitdepth(bad) == nil, "bitdepth should reject: " .. tostring(bad))
end

-- -- saved setups -----------------------------------------------------------
-- saved() reads the hand-editable file, so it must survive it being missing,
-- corrupt, or the wrong shape -- an empty table is "never arranged".
local tmp = os.tmpname()
local realpath = d.PATH
d.PATH = tmp

local function write(text)
  local f = assert(io.open(tmp, "w")); f:write(text); f:close()
end

write('{"layouts":{"A|B":{"A":{"position":"0x0","disabled":true},"B":"junk"}},'
   .. '"outputs":{"A":{"scale":2},"C":7}}')
local setup, outputs = d.saved({ "B", "A" })   -- order independent
assert(setup.A.position == "0x0" and setup.A.disabled == true)
assert(setup.B == nil, "a non-table entry is dropped")
assert(outputs.A.scale == 2 and outputs.C == nil)
assert(next((d.saved({ "A" }))) == nil, "another set of screens is another setup")

for _, bad in ipairs({ '{ not json', '{"layouts":"nope","outputs":[]}', '[]' }) do
  write(bad)
  local s, o = d.saved({ "A", "B" })
  assert(next(s) == nil and next(o) == nil, "should read as empty: " .. bad)
end

os.remove(tmp)
local s, o = d.saved({ "A" })
assert(next(s) == nil and next(o) == nil)
d.PATH = realpath

print("conf selftest ok")
