-- Loads the real monitors.lua against a stubbed `hl` and a stubbed lid, and
-- asserts which outputs each hardware combination ends up configuring.
-- Run from the hypr config directory, so monitors.lua's own
-- require("conf/...") resolves: `lua tests/test-monitors.lua` from the package
-- tree, `lua test_monitors.lua` from ~/.config/hypr.
local PATH = arg[1] or "conf/monitors.lua"

local LG     = { name = "DP-3",  description = "LG Electronics LG ULTRAWIDE 0x0001ABCD" }
local IIYAMA = { name = "DP-3",  description = "Iiyama North America PL3466WQ 1174003000146" }
local EDP    = { name = "eDP-1", description = "BOE NE135A1M-NY1" }

local function run(monitors, lidClosed)
  local calls = {}
  _G.hl = {
    get_monitors = function() return monitors end,
    monitor = function(t) calls[#calls + 1] = t end,
    on = function() end,
    bind = function() end,
  }
  -- stub the lid read
  local realopen = io.open
  io.open = function(p, ...)
    if p:match("lid") then
      if lidClosed == nil then return nil end
      return { read = function() return lidClosed and "state: closed" or "state: open" end,
               close = function() end }
    end
    -- displays.json is the user's saved layout, and monitors.lua deliberately
    -- lets it override the profile's position and the catalog's mode/scale.
    -- Stub it empty: every case below asserts what PROFILES does, so whether
    -- the developer happens to have arranged this monitor set in the settings
    -- app must not decide whether the suite passes.
    if p:match("displays%.json$") then return nil end
    return realopen(p, ...)
  end
  -- monitors.lua resolves the lid directory with a glob, because firmware
  -- names it (LID0 here, LID elsewhere). Stub the glob as well as the read, or
  -- a build machine with no /proc/acpi/button/lid resolves no path at all and
  -- every lid-shut case silently reads as "open".
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
  return enabled, disabled
end

local fails = 0
local function check(label, monitors, lidClosed, wantEnabled, wantDisabled)
  local en, di = run(monitors, lidClosed)
  local got = table.concat(en, " | ") .. "   disabled: [" .. table.concat(di, ", ") .. "]"
  local want = table.concat(wantEnabled, " | ") .. "   disabled: [" .. table.concat(wantDisabled, ", ") .. "]"
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  print("          got:  " .. got)
  if not ok then print("          want: " .. want) end
end

print("== " .. PATH)
check("home: Iiyama + laptop, lid open", { IIYAMA, EDP }, false,
  { "desc:Iiyama North America PL3466WQ @ 0x0", "eDP-1 @ 1000x1440" }, {})
check("home: Iiyama + laptop, lid shut", { IIYAMA, EDP }, true,
  { "desc:Iiyama North America PL3466WQ @ 0x0" }, { "eDP-1" })
check("office: LG + laptop, lid open", { LG, EDP }, false,
  { "desc:LG Electronics LG ULTRAWIDE @ 0x0", "eDP-1 @ 1000x1440" }, {})
check("road: laptop only", { EDP }, false, { "eDP-1 @ 0x0" }, {})

os.exit(fails == 0 and 0 or 1)
