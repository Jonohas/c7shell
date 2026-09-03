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
  active = "office", forced = true,
  profiles = { { name = "office", source = "lua", available = true,
                 displays = { ["LG x"] = { position = "0x0", scale = 1 } } } },
}))
assert(round.active == "office" and round.forced == true)
assert(round.profiles[1].displays["LG x"].position == "0x0")
assert(round.profiles[1].displays["LG x"].scale == 1)

-- write_state round-trips through a real file and reports failure rather than
-- raising: a settings page that cannot show its picker beats a config reload
-- that errors out.
local tmp = os.tmpname()
assert(d.write_state({ active = "x" }, tmp) == true)
assert(json.decode(json.read_file(tmp)).active == "x")
os.remove(tmp)
assert(d.write_state({ active = "x" }, "/proc/nonexistent/nope.json") == false)

print("conf selftest ok")
