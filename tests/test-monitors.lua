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
  local calls, state, off, binds, handlers, timers = {}, nil, {}, {}, {}, {}
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
    on = function(event, fn) handlers[event] = fn end,
    bind = function(key, fn) binds[key] = fn end,
    -- Close enough to hl's timers: monitors.lua only ever restarts one
    -- (disable, set_timeout, enable) and never cancels one that has fired.
    -- Nothing fires on its own; a case calls elapse() to run what the timer
    -- holds. Two are registered: the hotplug debounce first, the lid poll last.
    timer = function(fn, opts)
      local t = { fn = fn, timeout = opts and opts.timeout, fired = 0, enabled = false }
      function t:set_enabled(on) self.enabled = on end
      function t:set_timeout(ms) self.timeout = ms end
      function t:elapse()
        if not self.enabled then return end
        self.enabled = false
        self.fired = self.fired + 1
        self.fn()
      end
      timers[#timers + 1] = t
      return t
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
    -- displays-state.json is written every apply and read once at load, for
    -- the screens the last run parked. Capture the write and serve STATE_IN to
    -- the read, so the suite never touches the developer's real ~/.config.
    if p:match("displays%-state%.json$") then
      if mode == "w" then
        return { write = function(_, text) state = text end, close = function() end }
      end
      if not STATE_IN then return nil end
      return { read = function() return STATE_IN end, close = function() end }
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
  if after then after(binds, function(closed) lid = closed end, timers, handlers) end
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
  return enabled, disabled, state, specs, { handlers = handlers, timer = timers[1],
                                            calls = calls }
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

local DELL = { name = "DP-4", description = "Dell Inc. DELL P2417H CW6Y778H51UB" }
local PROJ = { name = "HDMI-A-1", description = "Acme Projector 42" }
local function at(m) return "desc:" .. m.description end
local function key(...)
  local d = {}
  for _, m in ipairs({ ... }) do d[#d + 1] = m.description end
  table.sort(d)
  return table.concat(d, "|")
end
-- A displays.json with one saved setup, `fields` keyed by monitor.
local function layout(k, fields)
  local body = {}
  for m, f in pairs(fields) do body[#body + 1] = '"' .. m.description .. '":' .. f end
  return '{"layouts":{"' .. k .. '":{' .. table.concat(body, ",") .. '}}}'
end

-- -- a set of screens never arranged ----------------------------------------
-- No names and no hand-written layout: every screen on, Hyprland's auto
-- places them. The shut lid is the one thing still decided here.
check("new desk: LG + laptop, lid open", { LG, EDP }, false,
  { at(EDP) .. " @ auto", at(LG) .. " @ auto" }, {})
check("new desk: LG + laptop, lid shut", { LG, EDP }, true,
  { at(LG) .. " @ auto" }, { at(EDP) })
check("road: laptop only", { EDP }, false, { at(EDP) .. " @ auto" }, {})
-- Better a panel under a shut lid than no output at all.
check("lid shut with nothing else plugged in keeps the panel", { EDP }, true,
  { at(EDP) .. " @ auto" }, {})
-- A projector is configured like anything else connected; nothing turns a
-- screen off unless a saved setup says so.
check("an unknown monitor is put on auto, not disabled", { EDP, PROJ }, false,
  { at(PROJ) .. " @ auto", at(EDP) .. " @ auto" }, {})

-- -- saved setups -----------------------------------------------------------
check("a saved setup restores its positions", { LG, EDP }, false,
  { at(EDP) .. " @ 1000x1440", at(LG) .. " @ 0x0" }, {},
  layout(key(LG, EDP), { [LG] = '{"position":"0x0"}', [EDP] = '{"position":"1000x1440"}' }))
-- The lid takes the panel out of the set, so lid-shut is its own setup and the
-- open-lid one is not applied to it.
check("lid shut reads as its own setup", { LG, EDP }, true,
  { at(LG) .. " @ auto" }, { at(EDP) },
  layout(key(LG, EDP), { [LG] = '{"position":"500x0"}' }))
check("a screen missing from a saved setup goes to auto", { LG, EDP }, false,
  { at(EDP) .. " @ auto", at(LG) .. " @ 0x0" }, {},
  layout(key(LG, EDP), { [LG] = '{"position":"0x0"}' }))
check("an invalid saved position goes to auto", { LG, EDP }, false,
  { at(EDP) .. " @ auto", at(LG) .. " @ auto" }, {},
  layout(key(LG, EDP), { [LG] = '{"position":"999999x0"}' }))

-- -- switched off -----------------------------------------------------------
check("a setup can switch a screen off", { LG, DELL, EDP }, false,
  { at(EDP) .. " @ auto", at(LG) .. " @ auto" }, { at(DELL) },
  layout(key(LG, DELL, EDP), { [DELL] = '{"disabled":true}' }))
check("a setup that switches every screen off is not honoured", { EDP }, false,
  { at(EDP) .. " @ auto" }, {},
  layout(key(EDP), { [EDP] = '{"disabled":true}' }))

-- -- field fallback ---------------------------------------------------------
local function checkField(label, monitors, displaysJson, output, field, want)
  local _, _, _, specs = run(monitors, false, displaysJson)
  local got = specs[output] and specs[output][field]
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  if not ok then print("          got: " .. tostring(got) .. "  want: " .. tostring(want)) end
end

-- Nothing in this file names a monitor: a panel never set up is left to
-- Hyprland, whatever it is.
checkField("a panel never set up gets hyprland's preferred mode", { LG, EDP }, nil,
  at(LG), "mode", "preferred")
checkField("a panel never set up gets hyprland's auto scale", { LG, EDP }, nil,
  at(EDP), "scale", "auto")
checkField("a hand-written bitdepth in the per-screen memory is applied", { LG, EDP },
  '{"outputs":{"' .. LG.description .. '":{"bitdepth":10}}}', at(LG), "bitdepth", 10)
checkField("a bitdepth other than 8 or 10 is refused", { LG, EDP },
  '{"outputs":{"' .. LG.description .. '":{"bitdepth":12}}}', at(LG), "bitdepth", nil)
-- KDE's per-output memory: a panel seen before brings its settings into a
-- set of screens that has never been arranged.
checkField("the per-screen memory carries scale into a new setup", { LG, EDP },
  '{"outputs":{"' .. LG.description .. '":{"scale":1.5}}}', at(LG), "scale", 1.5)
checkField("the setup's own value beats the per-screen memory", { LG, EDP },
  '{"layouts":{"' .. key(LG, EDP) .. '":{"' .. LG.description .. '":{"scale":1.25}}},'
    .. '"outputs":{"' .. LG.description .. '":{"scale":1.5}}}', at(LG), "scale", 1.25)
checkField("a saved rotation reaches hl.monitor()", { LG, EDP },
  layout(key(LG, EDP), { [LG] = '{"transform":1}' }), at(LG), "transform", 1)
checkField("a flipped saved rotation is refused", { LG, EDP },
  layout(key(LG, EDP), { [LG] = '{"transform":6}' }), at(LG), "transform", nil)
checkField("a saved mode the panel does not list falls back", { LG, EDP },
  layout(key(LG, EDP), { [LG] = '{"mode":"3440x1440@144.00"}' }), at(LG), "mode",
  "preferred")

-- -- the state file ---------------------------------------------------------
-- The settings app saves under the setup this file matched, so it has to be
-- the one it will look up again: lid and parked screens included.
local function checkState(label, fn, monitors, lidClosed, displaysJson, after)
  local _, _, state = run(monitors, lidClosed, displaysJson, after)
  local ok, err = pcall(fn, state and json.decode(state))
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  if not ok then print("          " .. tostring(err)) end
end

checkState("state names the setup and its screens", function(s)
  assert(s, "no state written")
  assert(s.setup == key(LG, EDP), "setup was " .. tostring(s.setup))
  assert(#s.screens == 2 and #s.parked == 0)
end, { LG, EDP }, false)
checkState("a shut lid is not in the setup", function(s)
  assert(s.setup == key(LG), "setup was " .. tostring(s.setup))
end, { LG, EDP }, true)

-- Hyprland hides a disabled screen, so the next apply cannot see it. If it
-- dropped out of the key, switching a screen off would make the desk a
-- different setup and the layout that switched it off would never apply again.
local DESK = layout(key(LG, DELL, EDP), { [DELL] = '{"disabled":true}', [LG] = '{"position":"0x0"}' })
checkState("a parked screen stays in the setup on the next apply", function(s)
  assert(s.setup == key(LG, DELL, EDP), "setup was " .. tostring(s.setup))
  assert(s.parked[1] == DELL.description)
end, { LG, DELL, EDP }, false, DESK, function(_, _, timers)
  timers[1]:set_enabled(true)
  timers[1]:elapse()
end)

-- The dock comes off: the parked Dell may be gone too, and nothing here can
-- tell, so it is woken blind and drops out of the set.
local woke
checkState("undocking drops the parked screen and wakes it", function(s)
  assert(s.setup == key(EDP), "setup was " .. tostring(s.setup))
  assert(#s.parked == 0)
  assert(woke, "the parked screen was not woken")
end, { LG, DELL, EDP }, false, DESK, function(_, _, timers)
  local mons = _G.hl.get_monitors
  local realmonitor = _G.hl.monitor
  _G.hl.get_monitors = function()
    local out = {}
    for _, m in ipairs(mons()) do if m == EDP then out[#out + 1] = m end end
    return out
  end
  _G.hl.monitor = function(t)
    if t.output == at(DELL) and t.disabled == false then woke = true end
    realmonitor(t)
  end
  timers[1]:set_enabled(true)
  timers[1]:elapse()
end)

-- Shutting the lid changes the setup but not the desk: the Dell stays parked
-- rather than being woken blind and switched off again.
checkState("shutting the lid does not wake a parked screen", function(s)
  assert(not woke, "the parked screen was woken")
  assert(s.setup == key(LG, DELL), "setup was " .. tostring(s.setup))
end, { LG, DELL, EDP }, false,
  '{"layouts":{"' .. key(LG, DELL, EDP) .. '":{"' .. DELL.description .. '":{"disabled":true}},'
    .. '"' .. key(LG, DELL) .. '":{"' .. DELL.description .. '":{"disabled":true}}}}',
  function(_, setLid, timers)
    woke = nil
    local realmonitor = _G.hl.monitor
    _G.hl.monitor = function(t)
      if t.output == at(DELL) and t.disabled == false then woke = true end
      realmonitor(t)
    end
    setLid(true)
    timers[1]:set_enabled(true)
    timers[1]:elapse()
    _G.hl.monitor = realmonitor
  end)

-- A reload starts with nothing in memory: the screens the last run parked come
-- from the state file and are woken, so the setup is matched against the real
-- desk and then switches them off again.
STATE_IN = '{"parked":["' .. DELL.description .. '"]}'
checkWake = function(label, monitors, offDesc, displaysJson, wantEnabled, wantDisabled)
  local en, di = run(monitors, false, displaysJson, nil, offDesc)
  local got = table.concat(en, " | ") .. "   disabled: [" .. table.concat(di, ", ") .. "]"
  local want = table.concat(wantEnabled, " | ") .. "   disabled: [" .. table.concat(wantDisabled, ", ") .. "]"
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  print("          got:  " .. got)
  if not ok then print("          want: " .. want) end
end
checkWake("a screen parked before a reload is woken and parked again", { LG, DELL, EDP },
  DELL.description, DESK, { at(EDP) .. " @ auto", at(LG) .. " @ 0x0" }, { at(DELL) })
STATE_IN = nil
-- The panel is the one screen woken by name with nothing parked: a reload
-- with it switched off by the lid must not leave it dark once the lid is open.
checkWake("a built-in panel left disabled is enabled again at load", { LG, EDP },
  EDP.description, nil, { at(EDP) .. " @ auto", at(LG) .. " @ auto" }, {})

-- -- the lid, closed and open again -----------------------------------------
-- apply() disables the panel on lid close, Hyprland then hides it, and the
-- switch bind on reopen found nothing to turn back on. wake_panel() enables it
-- blind first ("eDP-1 @ auto"), then the setup lays it out.
local function lidCalls(monitors, displaysJson, trigger)
  local calls = {}
  run(monitors, true, displaysJson, function(binds, setLid, timers)
    setLid(false)
    local realmonitor = _G.hl.monitor
    _G.hl.monitor = function(t) calls[#calls + 1] = t; realmonitor(t) end
    trigger(binds, timers)
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
  return table.concat(enabled, " | ") .. "   disabled: [" .. table.concat(disabled, ", ") .. "]"
end
local function checkLid(label, monitors, displaysJson, trigger, wantEnabled)
  local got = lidCalls(monitors, displaysJson, trigger)
  local want = table.concat(wantEnabled, " | ") .. "   disabled: []"
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  print("          got:  " .. got)
  if not ok then print("          want: " .. want) end
end
local reopen = function(binds) binds["switch:off:Lid Switch"]() end
-- A switch event can go missing; the poll is what catches it.
local poll = function(_, timers) timers[#timers].fn() end
local OPEN = layout(key(LG, EDP), { [LG] = '{"position":"0x0"}', [EDP] = '{"position":"1000x1440"}' })

checkLid("reopening the lid brings the panel back", { LG, EDP }, nil, reopen,
  { at(EDP) .. " @ auto", at(LG) .. " @ auto", "eDP-1 @ auto" })
checkLid("reopening the lid restores the open-lid setup", { LG, EDP }, OPEN, reopen,
  { at(EDP) .. " @ 1000x1440", at(LG) .. " @ 0x0", "eDP-1 @ auto" })
checkLid("the poll recovers a lid-open that fired no switch event", { LG, EDP }, OPEN, poll,
  { at(EDP) .. " @ 1000x1440", at(LG) .. " @ 0x0", "eDP-1 @ auto" })

-- -- hotplug ----------------------------------------------------------------
-- A dock's connectors do not come back together. Applying straight off
-- monitor.added saw a partial set and locked in the wrong setup, and nothing
-- re-triggered once the rest arrived, so the events are debounced instead.
local function checkHotplug(label, fn)
  local ok, err = pcall(fn)
  if not ok then fails = fails + 1 end
  print((ok and "  PASS  " or "  FAIL  ") .. label)
  if not ok then print("          " .. tostring(err)) end
end

checkHotplug("a burst of hotplug events applies once, after it goes quiet", function()
  local err
  -- Inside run(), so the apply the timer fires writes the stubbed state file
  -- and not the developer's real one.
  run({ LG, EDP }, false, nil, function(_, _, timers, handlers)
    local ok, e = pcall(function()
      local calls = 0
      local realmonitor = _G.hl.monitor
      _G.hl.monitor = function(t) calls = calls + 1; realmonitor(t) end
      assert(handlers["monitor.added"], "monitor.added is not handled")
      handlers["monitor.added"]()
      handlers["monitor.added"]()
      handlers["monitor.removed"]()
      local t = timers[1]
      assert(calls == 0, "the burst applied before settling")
      t:elapse()
      assert(calls > 0, "nothing applied once the burst went quiet")
      assert(t.fired == 1, "applied " .. t.fired .. " times for one burst")
      _G.hl.monitor = realmonitor
    end)
    err = not ok and e or nil
  end)
  if err then error(err) end
end)

checkHotplug("the hotplug listeners are registered before the first apply", function()
  -- A monitor.added that fires while Hyprland is still enumerating outputs is
  -- for a display that will not hotplug again; with the listener registered
  -- after apply(), that event was lost and the layout stayed stuck.
  local _, _, _, _, hp = run({ EDP }, false)
  assert(hp.handlers["monitor.added"], "no monitor.added handler after load")
  assert(hp.handlers["monitor.removed"], "no monitor.removed handler after load")
end)

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
