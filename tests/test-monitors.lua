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

-- The stub models the one thing that bit: Hyprland drops a DISABLED monitor
-- from its monitor list entirely, so conf/monitors.lua cannot see a panel it
-- switched off -- and that is why reopening the lid never brought the built-in
-- one back. `off` is that hidden set; hl.monitor() moves panels in and out of it
-- exactly as the compositor does.
local function run(monitors, lidClosed, displaysJson, after, offDesc)
  local calls, state, off, binds, timers = {}, nil, {}, {}, {}
  -- The lid moves: ACPI is what conf/monitors.lua trusts, so a case that opens
  -- the lid has to move this, not just fire the bind.
  local lid = lidClosed
  -- A panel a previous run disabled: hidden from get_monitors() exactly as
  -- Hyprland hides it, until something enables it again.
  if offDesc then off[offDesc] = true end
  local function resolve(output)
    local desc = output:match("^desc:(.+)$")
    for _, m in ipairs(monitors) do
      if desc then
        if m.description:sub(1, #desc) == desc then return m end
      elseif m.name == output then return m end
    end
  end
  _G.hl = {
    get_monitors = function()
      local live = {}
      for _, m in ipairs(monitors) do
        if not off[m.description] then live[#live + 1] = m end
      end
      return live
    end,
    monitor = function(t)
      calls[#calls + 1] = t
      local m = t.output ~= "" and resolve(t.output)
      if m and t.disabled ~= nil then off[m.description] = t.disabled or nil end
    end,
    on = function() end,
    bind = function(key, fn) binds[key] = fn end,
    -- The hotplug debounce hands apply() to a timer. Fire it immediately: the
    -- suite asserts what a settled burst produces, not how long it waits.
    -- Two timers use this: the hotplug debounce, which the suite wants to fire
    -- at once, and the lid poll, which rearms itself and would recurse for ever
    -- if it did. Fire each callback once per enable, and only on the first.
    timer = function(fn)
      timers[#timers + 1] = fn
      local fired = false
      return { set_enabled = function(_, on)
                 if on and not fired then fired = true; fn() end
               end,
               set_timeout = function() end }
    end,
  }
  local realopen = io.open
  io.open = function(p, mode, ...)
    if p:match("lid") then
      if lid == nil then return nil end
      return { read = function() return lid and "state: closed" or "state: open" end,
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
  -- Anything that pokes the binds runs HERE, with the stubbed io still in
  -- place: a lid bind re-reads displays.json and rewrites the state file, and
  -- letting that reach the real ~/.config would both skew the test and scribble
  -- on the developer's desk.
  if after then after(binds, function(closed) lid = closed end, timers) end
  io.open = realopen
  io.popen = realpopen

  local enabled, disabled, specs = {}, {}, {}
  for _, c in ipairs(calls) do
    -- A bare enable -- no position, no mode -- is wake_all() clearing an
    -- earlier disable, not a layout decision. Cases assert the layout, so
    -- those calls are noise here; the wake case reads the layout that follows.
    local wake = c.disabled == false and c.position == nil and c.mode == nil
    if c.output ~= "" and not wake then
      -- Keyed by output so a case can also inspect a field check() does not
      -- compare, e.g. the resolved mode.
      specs[c.output] = c
      if c.disabled == true then disabled[#disabled + 1] = c.output
      else enabled[#enabled + 1] = c.output .. " @ " .. tostring(c.position) end
    end
  end
  table.sort(enabled); table.sort(disabled)
  return enabled, disabled, state, specs, binds, calls
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

-- The office desk keeps its second screen when the lid shuts. Without a profile
-- naming both, ultrawide-lid-closed matched on the ultrawide alone and the Dell
-- went dark, because a known display outside the winning profile is disabled.
local DELL = { name = "DP-4", description = "Dell Inc. DELL P2417H CW6Y778H51UB" }
check("office: LG + Dell + laptop, lid shut", { LG, DELL, EDP }, true,
  { "desc:Dell Inc. DELL P2417H @ 3440x180",
    "desc:LG Electronics LG ULTRAWIDE @ 0x0" }, { "eDP-1" })

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

-- -- a screen an earlier run disabled ---------------------------------------
-- The same blindness as the lid, one step further out: a disabled monitor is
-- gone from hl.get_monitors(), so a profile that switched an external screen
-- off left nothing able to switch it back on. Load re-enables every CATALOG
-- panel first, so the choice is made against the real desk.
local function checkWake(label, monitors, offDesc, wantEnabled, wantDisabled)
  local en, di = run(monitors, false, nil, nil, offDesc)
  local got = table.concat(en, " | ") .. "   disabled: [" .. table.concat(di, ", ") .. "]"
  local want = table.concat(wantEnabled, " | ") .. "   disabled: [" .. table.concat(wantDisabled, ", ") .. "]"
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  print("          got:  " .. got)
  if not ok then print("          want: " .. want) end
end

-- Without the wake the LG is invisible, only the laptop is left, and the desk
-- comes up on `mobile` -- which is exactly what a reload did here.
checkWake("a screen left disabled is enabled again at load", { LG, EDP }, LG.description,
  { "desc:LG Electronics LG ULTRAWIDE @ 0x0", "eDP-1 @ 1000x1440" }, {})

-- -- the lid, closed and open again -----------------------------------------
-- The regression this stub exists for: apply() disables eDP-1 on lid close,
-- Hyprland then hides that panel from the monitor list, and the switch bind on
-- reopen found nothing to turn back on. The laptop stayed dark until a reload.
local function checkLid(label, monitors, displaysJson, wantEnabled, wantDisabled)
  local calls = {}
  run(monitors, true, displaysJson, function(binds, setLid)
    local open = binds["switch:off:Lid Switch"]
    if not open then error("no lid-open bind") end
    setLid(false)
    -- Only the calls the REOPEN makes; the load with the lid shut is setup.
    local realmonitor = _G.hl.monitor
    _G.hl.monitor = function(t) calls[#calls + 1] = t; realmonitor(t) end
    open()
    _G.hl.monitor = realmonitor
  end)

  local enabled, disabled = {}, {}
  for _, c in ipairs(calls) do
    if c.output ~= "" then
      if c.disabled == true then disabled[#disabled + 1] = c.output
      else enabled[#enabled + 1] = c.output .. " @ " .. tostring(c.position) end
    end
  end
  table.sort(enabled); table.sort(disabled)
  local got = table.concat(enabled, " | ") .. "   disabled: [" .. table.concat(disabled, ", ") .. "]"
  local want = table.concat(wantEnabled, " | ") .. "   disabled: [" .. table.concat(wantDisabled, ", ") .. "]"
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  print("          got:  " .. got)
  if not ok then print("          want: " .. want) end
end

-- eDP-1 comes back on (once blind, once in the profile) and the layout returns
-- to the lid-open profile.
checkLid("reopening the lid brings the built-in panel back", { LG, EDP }, nil,
  { "desc:LG Electronics LG ULTRAWIDE @ 0x0", "eDP-1 @ 1000x1440", "eDP-1 @ auto" }, {})

-- Same for a JSON profile: the panel it names is only matchable once it is
-- visible again.
checkLid("reopening the lid re-matches a json profile", { LG, EDP },
  json_profiles('{"name":"json-desk","displays":{'
    .. LG_AT .. ':{"position":"0x0"},' .. EDP_AT .. ':{"position":"0x1440"}}}'),
  { "desc:BOE NE135A1M-NY1 @ 0x1440", "desc:LG Electronics LG ULTRAWIDE 0x0001ABCD @ 0x0",
    "eDP-1 @ auto" }, {})

-- Same recovery with no switch event at all: the poll is what makes the lid
-- reliable, because a missing "switch:off" is exactly what stranded the desk
-- in the lid-closed profile with the lid open.
local function checkLidPoll(label, monitors, wantEnabled, wantDisabled)
  local calls = {}
  run(monitors, true, nil, function(_, setLid, timers)
    local poll = timers[#timers] -- the lid poll is the last timer registered
    if not poll then error("no lid poll timer") end
    setLid(false)
    local realmonitor = _G.hl.monitor
    _G.hl.monitor = function(t) calls[#calls + 1] = t; realmonitor(t) end
    poll()
    _G.hl.monitor = realmonitor
  end)

  local enabled, disabled = {}, {}
  for _, c in ipairs(calls) do
    local wake = c.disabled == false and c.position == nil and c.mode == nil
    if c.output ~= "" and not wake then
      if c.disabled == true then disabled[#disabled + 1] = c.output
      else enabled[#enabled + 1] = c.output .. " @ " .. tostring(c.position) end
    end
  end
  table.sort(enabled); table.sort(disabled)
  local got = table.concat(enabled, " | ") .. "   disabled: [" .. table.concat(disabled, ", ") .. "]"
  local want = table.concat(wantEnabled, " | ") .. "   disabled: [" .. table.concat(wantDisabled, ", ") .. "]"
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  print("          got:  " .. got)
  if not ok then print("          want: " .. want) end
end

checkLidPoll("the poll recovers a lid-open that fired no switch event", { LG, EDP },
  { "desc:LG Electronics LG ULTRAWIDE @ 0x0", "eDP-1 @ 1000x1440", "eDP-1 @ auto" }, {})

-- -- no profile fits --------------------------------------------------------
-- Everything connected goes back to preferred/auto. Leaving it alone was the
-- bug: a screen an earlier profile disabled had nothing left to re-enable it.
-- lidClosed = nil is a machine with no lid at all, i.e. a desktop whose only
-- screen is one nothing in CATALOG or PROFILES knows.
local PROJ = { name = "HDMI-A-1", description = "Acme Projector 42" }
check("no matching profile falls back to auto", { PROJ }, nil,
  { "HDMI-A-1 @ auto" }, {})

-- -- rotation ---------------------------------------------------------------
-- A profile saved from a rotated screen keeps the rotation; it used to be
-- dropped on the way through displays.json and the screen came back landscape.
local function checkTransform(label, monitors, displaysJson, wantOutput, wantTransform)
  local _, _, _, specs = run(monitors, false, displaysJson)
  local got = specs[wantOutput] and specs[wantOutput].transform
  local ok = got == wantTransform
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  if not ok then print("          got: " .. tostring(got) .. "  want: " .. tostring(wantTransform)) end
end

checkTransform("a json profile applies its rotation", { LG, EDP },
  json_profiles('{"name":"portrait","displays":{'
    .. LG_AT .. ':{"position":"0x0","transform":1}}}'),
  "desc:LG Electronics LG ULTRAWIDE 0x0001ABCD", 1)

checkTransform("a flipped transform in a profile is refused", { LG, EDP },
  json_profiles('{"name":"portrait","displays":{'
    .. LG_AT .. ':{"position":"0x0","transform":6}}}'),
  "desc:LG Electronics LG ULTRAWIDE 0x0001ABCD", nil)

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

-- displays.transform is the whitelist the saved-layout rotation passes through.
-- A stray value reaching hl.monitor() can rotate a screen to something the user
-- cannot read, so this refuses everything outside Hyprland's 0..3.
local displays = require("conf/displays")
local function checkT(label, v, want)
  local got = displays.transform(v)
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  if not ok then print("          got: " .. tostring(got) .. "  want: " .. tostring(want)) end
end

checkT("transform 0 is kept",        0,       0)
checkT("transform 3 is kept",        3,       3)
checkT("transform 4 (flipped) refused", 4,    nil)
checkT("transform -1 refused",      -1,       nil)
checkT("fractional transform refused", 1.5,   nil)
checkT("string transform refused",  "1",      nil)

os.exit(fails == 0 and 0 or 1)
