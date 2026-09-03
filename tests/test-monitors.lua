-- Loads the real monitors.lua against a stubbed `hl` and a stubbed lid, and
-- asserts which outputs each hardware combination ends up configuring.
-- Run from the hypr config directory, so monitors.lua's own
-- require("conf/...") resolves: `lua tests/test-monitors.lua` from the package
-- tree, `lua test_monitors.lua` from ~/.config/hypr.
local PATH = arg[1] or "conf/monitors.lua"
local json = require("conf/json")

local LG     = { name = "DP-3",  description = "LG Electronics LG ULTRAWIDE 0x0001ABCD" }
local IIYAMA = { name = "DP-3",  description = "Iiyama North America PL3466WQ 1174003000146" }
local EDP    = { name = "eDP-1", description = "BOE NE135A1M-NY1" }

local function run(monitors, lidClosed, displaysJson)
  local calls, state = {}, nil
  _G.hl = {
    get_monitors = function() return monitors end,
    monitor = function(t) calls[#calls + 1] = t end,
    on = function() end,
    bind = function() end,
  }
  local realopen = io.open
  io.open = function(p, mode, ...)
    if p:match("lid") then
      if lidClosed == nil then return nil end
      return { read = function() return lidClosed and "state: closed" or "state: open" end,
               close = function() end }
    end
    -- displays.json is the user's saved layout AND, since profiles landed, the
    -- profiles the settings app wrote. Each case says what it wants to see
    -- there; nil means the file does not exist, which is the common case.
    if p:match("displays%.json$") then
      if not displaysJson then return nil end
      return { read = function() return displaysJson end, close = function() end }
    end
    -- displays-state.json is written, not read. Capture it instead of letting
    -- the suite scribble in the developer's real ~/.config.
    if p:match("displays%-state%.json$") then
      return { write = function(_, text) state = text end, close = function() end }
    end
    return realopen(p, mode, ...)
  end
  local realpopen = io.popen
  io.popen = function(cmd, ...)
    if cmd:match("lid") then
      return { read = function() return "/proc/acpi/button/lid/LID0/state" end,
               close = function() end }
    end
    return realpopen(cmd, ...)
  end

  local chunk = assert(loadfile(PATH))
  chunk()
  io.open = realopen
  io.popen = realpopen

  local enabled, disabled, specs = {}, {}, {}
  for _, c in ipairs(calls) do
    if c.output ~= "" then
      -- Keyed by output so a case can also inspect a field check() does not
      -- compare, e.g. the resolved mode.
      specs[c.output] = c
      if c.disabled == true then disabled[#disabled + 1] = c.output
      else enabled[#enabled + 1] = c.output .. " @ " .. tostring(c.position) end
    end
  end
  table.sort(enabled); table.sort(disabled)
  return enabled, disabled, state, specs
end

local fails = 0
local function check(label, monitors, lidClosed, wantEnabled, wantDisabled, displaysJson)
  local en, di = run(monitors, lidClosed, displaysJson)
  local got = table.concat(en, " | ") .. "   disabled: [" .. table.concat(di, ", ") .. "]"
  local want = table.concat(wantEnabled, " | ") .. "   disabled: [" .. table.concat(wantDisabled, ", ") .. "]"
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  print("          got:  " .. got)
  if not ok then print("          want: " .. want) end
end

-- Same shape as check(), but asserts the resolved mode of one output instead
-- of the enabled/disabled sets -- the field check() has no way to see.
local function checkMode(label, monitors, lidClosed, displaysJson, wantOutput, wantMode)
  local _, _, _, specs = run(monitors, lidClosed, displaysJson)
  local got = specs[wantOutput] and specs[wantOutput].mode
  local ok = got == wantMode
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  print("          got:  " .. tostring(got))
  if not ok then print("          want: " .. tostring(wantMode)) end
end

print("== " .. PATH)

-- -- the lua PROFILES, unchanged by the arrival of JSON ones -----------------
check("home: Iiyama + laptop, lid open", { IIYAMA, EDP }, false,
  { "desc:Iiyama North America PL3466WQ @ 0x0", "eDP-1 @ 1000x1440" }, {})
check("home: Iiyama + laptop, lid shut", { IIYAMA, EDP }, true,
  { "desc:Iiyama North America PL3466WQ @ 0x0" }, { "eDP-1" })
check("office: LG + laptop, lid open", { LG, EDP }, false,
  { "desc:LG Electronics LG ULTRAWIDE @ 0x0", "eDP-1 @ 1000x1440" }, {})
check("road: laptop only", { EDP }, false, { "eDP-1 @ 0x0" }, {})

-- -- JSON profiles ----------------------------------------------------------
local function json_profiles(body) return '{"profiles":[' .. body .. ']}' end
local LG_AT = '"' .. LG.description .. '"'
local EDP_AT = '"' .. EDP.description .. '"'

-- A JSON profile is a candidate like any other, matched on the descriptions it
-- names. It sits ahead of the lua ones, so it wins where both fit.
check("json profile beats the lua one it does not shadow", { LG, EDP }, false,
  { "desc:BOE NE135A1M-NY1 @ 0x1440", "desc:LG Electronics LG ULTRAWIDE 0x0001ABCD @ 0x0" }, {},
  json_profiles('{"name":"json-desk","displays":{'
    .. LG_AT .. ':{"position":"0x0"},' .. EDP_AT .. ':{"position":"0x1440"}}}'))

-- Same name as a lua profile: the JSON one shadows it rather than both running.
check("json profile shadows the lua profile of the same name", { LG, EDP }, false,
  { "desc:BOE NE135A1M-NY1 @ 0x2000", "desc:LG Electronics LG ULTRAWIDE 0x0001ABCD @ 0x0" }, {},
  json_profiles('{"name":"ultrawide","displays":{'
    .. LG_AT .. ':{"position":"0x0"},' .. EDP_AT .. ':{"position":"0x2000"}}}'))

-- A display the profile does not name is off. That is what "profile" has always
-- meant here; it now applies to JSON profiles too.
check("a display absent from the json profile is disabled", { LG, EDP }, false,
  { "desc:LG Electronics LG ULTRAWIDE 0x0001ABCD @ 0x0" }, { "eDP-1" },
  json_profiles('{"name":"lg-only","displays":{' .. LG_AT .. ':{"position":"0x0"}}}'))

-- The lid still decides, and it decides first: a profile naming the built-in
-- panel cannot match with the lid shut, so the lua lid-closed profile takes it.
check("lid shut skips a json profile that names the laptop", { LG, EDP }, true,
  { "desc:LG Electronics LG ULTRAWIDE @ 0x0" }, { "eDP-1" },
  json_profiles('{"name":"json-desk","displays":{'
    .. LG_AT .. ':{"position":"0x0"},' .. EDP_AT .. ':{"position":"0x1440"}}}'))

-- A profile naming a monitor that is not plugged in does not match.
check("json profile with an absent display is skipped", { LG, EDP }, false,
  { "desc:LG Electronics LG ULTRAWIDE @ 0x0", "eDP-1 @ 1000x1440" }, {},
  json_profiles('{"name":"other-desk","displays":{"Some Other Panel":{"position":"0x0"}}}'))

-- -- mode validation ----------------------------------------------------------
-- A JSON mode is whitelisted against available_modes; the old `cond and a or b`
-- line handed back the raw, unvalidated string on a reject instead of nil.
local LG_MODES = { name = LG.name, description = LG.description,
  available_modes = { { width = 3440, height = 1440, refresh_rate = 100.0 } } }

checkMode("json mode absent from available_modes falls back to preferred",
  { LG_MODES, EDP }, false,
  json_profiles('{"name":"lg-only","displays":{' .. LG_AT .. ':{"position":"0x0","mode":"1920x1080@60"}}}'),
  "desc:LG Electronics LG ULTRAWIDE 0x0001ABCD", "preferred")

checkMode("json mode present in available_modes is used",
  { LG_MODES, EDP }, false,
  json_profiles('{"name":"lg-only","displays":{' .. LG_AT .. ':{"position":"0x0","mode":"3440x1440@100"}}}'),
  "desc:LG Electronics LG ULTRAWIDE 0x0001ABCD", "3440x1440@100")

-- -- the active override ----------------------------------------------------
-- Pinning a profile picks it even though an earlier candidate also fits.
check("active pins a profile that is not first", { LG, EDP }, false,
  { "desc:LG Electronics LG ULTRAWIDE 0x0001ABCD @ 0x0" }, { "eDP-1" },
  '{"active":"second","profiles":['
    .. '{"name":"first","displays":{' .. LG_AT .. ':{"position":"500x0"},' .. EDP_AT .. ':{"position":"0x1440"}}},'
    .. '{"name":"second","displays":{' .. LG_AT .. ':{"position":"0x0"}}}]}')

-- Pinning a lua profile by name works the same way.
check("active can pin a lua profile", { LG, EDP }, true,
  { "desc:LG Electronics LG ULTRAWIDE @ 0x0" }, { "eDP-1" },
  '{"active":"ultrawide-lid-closed"}')

-- An active name whose displays are absent falls back to auto-match rather than
-- leaving the desk unconfigured.
check("active naming an unavailable profile falls back to auto-match", { LG, EDP }, false,
  { "desc:LG Electronics LG ULTRAWIDE @ 0x0", "eDP-1 @ 1000x1440" }, {},
  '{"active":"nowhere","profiles":[{"name":"nowhere","displays":{"Some Other Panel":{"position":"0x0"}}}]}')

-- -- unknown monitors -------------------------------------------------------
-- A panel nothing knows about is left to the catch-all rule at the top of the
-- file, not disabled: a meeting-room projector must not go dark because the
-- laptop-only profile does not name it.
local PROJECTOR = { name = "HDMI-A-1", description = "Acme Projector 42" }
check("an unknown monitor is left alone, not disabled", { EDP, PROJECTOR }, false,
  { "eDP-1 @ 0x0" }, {})

-- -- the state file ---------------------------------------------------------
-- The settings app never reads conf/monitors.lua, so this document is the only
-- way it can list a profile that lives in lua, or say which one won.
local function checkState(label, fn, monitors, lidClosed, displaysJson)
  local _, _, state = run(monitors, lidClosed, displaysJson)
  local ok, err = pcall(fn, state and json.decode(state))
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  if not ok then print("          " .. tostring(err)) end
end

checkState("state lists the lua profiles and names the winner", function(s)
  assert(s, "no state written")
  assert(s.active == "ultrawide", "active was " .. tostring(s.active))
  assert(s.forced == false)
  local seen = {}
  for _, p in ipairs(s.profiles) do seen[p.name] = p end
  assert(seen["ultrawide"], "the winning lua profile is listed")
  assert(seen["mobile"], "a lua profile that does not fit is still listed")
  assert(seen["ultrawide"].source == "lua")
  assert(seen["ultrawide"].available == true)
  assert(seen["ultrawideHome"].available == false, "a profile whose screens are absent is listed, but not as available")
  assert(seen["ultrawide"].displays[LG.description].position == "0x0")
end, { LG, EDP }, false)

checkState("state marks a shadowed profile and the forced flag", function(s)
  local seen = {}
  for _, p in ipairs(s.profiles) do seen[p.name] = p end
  assert(seen["ultrawide"].source == "json", "the json profile took the name")
  assert(seen["ultrawide"].shadows == true, "and says so, so the page can offer revert")
  assert(s.active == "ultrawide")
  assert(s.forced == true)
  local n = 0
  for _, p in ipairs(s.profiles) do if p.name == "ultrawide" then n = n + 1 end end
  assert(n == 1, "the shadowed lua profile is not listed twice")
end, { LG, EDP }, false,
  '{"active":"ultrawide","profiles":[{"name":"ultrawide","displays":{"'
    .. LG.description .. '":{"position":"0x0"}}}]}')

checkState("state is written even when no profile matches", function(s)
  assert(s, "no state written")
  assert(s.active == nil)
  assert(s.forced == false)
end, { { name = "HDMI-A-1", description = "Acme Projector 42" } }, false)

os.exit(fails == 0 and 0 or 1)
