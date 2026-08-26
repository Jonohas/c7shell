------------------------
---- MINIMAL  JSON  ----
------------------------
-- Decoder for the JSON files the quickshell settings app writes
-- (appearance.json, displays.json). No Lua JSON library exists on this system,
-- so this is it. Recursive descent over the subset those files can contain:
-- objects, arrays, strings, numbers, true/false/null. No unicode escapes
-- beyond \uXXXX in the BMP-as-UTF-8 sense, which nothing here emits anyway.
--
-- Both files are hand-editable, so this returns nil on ANY malformed input
-- rather than a half-parsed table: callers fall back to their defaults, which
-- is the only safe reading of a file that is about to configure a compositor.

local M = {}

function M.read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local parse_value

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b",
                  f = "\f", n = "\n", r = "\r", t = "\t" }

local function skip_ws(s, i)
    return s:find("[^ \t\r\n]", i) or #s + 1
end

local function parse_string(s, i)
    -- s:sub(i, i) is the opening quote.
    local out, j = {}, i + 1
    while true do
        local c = s:sub(j, j)
        if c == "" then return nil end
        if c == '"' then return table.concat(out), j + 1 end
        if c == "\\" then
            local e = s:sub(j + 1, j + 1)
            if e == "u" then
                local hex = s:sub(j + 2, j + 5)
                if not hex:match("^%x%x%x%x$") then return nil end
                out[#out + 1] = utf8.char(tonumber(hex, 16))
                j = j + 6
            elseif ESCAPES[e] then
                out[#out + 1] = ESCAPES[e]
                j = j + 2
            else
                return nil
            end
        else
            out[#out + 1] = c
            j = j + 1
        end
    end
end

local function parse_object(s, i)
    local out, j = {}, skip_ws(s, i + 1)
    if s:sub(j, j) == "}" then return out, j + 1 end
    while true do
        if s:sub(j, j) ~= '"' then return nil end
        local key
        key, j = parse_string(s, j)
        if key == nil then return nil end
        j = skip_ws(s, j)
        if s:sub(j, j) ~= ":" then return nil end
        local val
        val, j = parse_value(s, skip_ws(s, j + 1))
        if j == nil then return nil end
        -- `null` decodes to nil, which cannot be stored: drop the key, which is
        -- what "absent" means to every caller here anyway.
        if val ~= nil then out[key] = val end
        j = skip_ws(s, j)
        local c = s:sub(j, j)
        if c == "}" then return out, j + 1 end
        if c ~= "," then return nil end
        j = skip_ws(s, j + 1)
    end
end

local function parse_array(s, i)
    local out, j = {}, skip_ws(s, i + 1)
    if s:sub(j, j) == "]" then return out, j + 1 end
    while true do
        local val
        val, j = parse_value(s, j)
        if j == nil then return nil end
        out[#out + 1] = val
        j = skip_ws(s, j)
        local c = s:sub(j, j)
        if c == "]" then return out, j + 1 end
        if c ~= "," then return nil end
        j = skip_ws(s, j + 1)
    end
end

parse_value = function(s, i)
    local c = s:sub(i, i)
    if c == '"' then return parse_string(s, i) end
    if c == "{" then return parse_object(s, i) end
    if c == "[" then return parse_array(s, i) end
    if s:sub(i, i + 3) == "true" then return true, i + 4 end
    if s:sub(i, i + 4) == "false" then return false, i + 5 end
    -- nil is not a distinguishable return, so null reports its end index and a
    -- nil value; the object/array parsers above treat that as "absent".
    if s:sub(i, i + 3) == "null" then return nil, i + 4 end
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if num and tonumber(num) then return tonumber(num), i + #num end
    return nil
end

--- Decode a whole JSON document. Returns nil if it is not valid.
function M.decode(text)
    if type(text) ~= "string" then return nil end
    local val, i = parse_value(text, skip_ws(text, 1))
    if i == nil or skip_ws(text, i) <= #text then return nil end
    return val
end

--- Decode a FLAT object of scalars, dropping anything with structure.
--- Never returns nil: a missing or corrupt file is an empty table, and the
--- caller's defaults fill it in.
function M.decode_flat(text)
    local obj, out = M.decode(text), {}
    if type(obj) ~= "table" then return out end
    for k, v in pairs(obj) do
        if type(v) ~= "table" then out[k] = v end
    end
    return out
end

return M
