-- Loads the real monitors.lua against a stubbed `hl` and a stubbed lid, and
-- asserts which outputs each hardware combination ends up configuring.
-- Run from the hypr config directory, so monitors.lua's own
-- require("conf/...") resolves: `lua tests/test-monitors.lua` from the package
-- tree, `lua test_monitors.lua` from ~/.config/hypr.
local PATH = arg[1] or "conf/monitors.lua"

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

  local enabled, disabled = {}, {}
  for _, c in ipairs(calls) do
    if c.output ~= "" then
      if c.disabled == true then disabled[#disabled + 1] = c.output
      else enabled[#enabled + 1] = c.output .. " @ " .. tostring(c.position) end
    end
  end
  table.sort(enabled); table.sort(disabled)
  return enabled, disabled, state
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

os.exit(fails == 0 and 0 or 1)
