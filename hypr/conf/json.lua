------------------------
---- MINIMAL  JSON  ----
------------------------
-- Decoder for a FLAT json object of scalars, which is all appearance.json ever
-- is. Not a general parser: no nested objects, no arrays, no unicode escapes.
-- If the file ever grows structure, replace this rather than extend it.

local M = {}

function M.read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

function M.decode_flat(text)
    local out = {}
    if not text then return out end

    -- String values first: a path containing a comma or a brace must not be
    -- split by the scalar pattern below.
    for k, v in text:gmatch('"([%w_]+)"%s*:%s*"([^"]*)"') do
        out[k] = (v:gsub('\\(.)', '%1'))
    end

    -- Then numbers, booleans, null.
    for k, v in text:gmatch('"([%w_]+)"%s*:%s*([^",}%s]+)') do
        if out[k] == nil then
            if v == "true" then out[k] = true
            elseif v == "false" then out[k] = false
            elseif v ~= "null" then out[k] = tonumber(v) end
        end
    end

    return out
end

return M
