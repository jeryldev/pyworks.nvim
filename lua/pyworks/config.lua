-- Minimal config module for backward compatibility
-- The real configuration is now in init.lua

local M = {}

function M.get_state(key)
    local state = require("pyworks.core.state")
    return state.get(key)
end

function M.set_state(key, value)
    local state = require("pyworks.core.state")
    state.set(key, value)
end

return M
