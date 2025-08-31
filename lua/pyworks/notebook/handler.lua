-- Notebook handler that gracefully handles missing jupytext
local M = {}

local notifications = require("pyworks.core.notifications")
local utils = require("pyworks.utils")

-- Check if jupytext CLI is available
function M.check_jupytext_cli()
    local handle = io.popen("which jupytext 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        return result and result ~= ""
    end
    return false
end

-- Handle notebook opening with fallback
function M.handle_notebook_open(filepath)
    -- Check if jupytext CLI is available
    if not M.check_jupytext_cli() then
        -- Get project info
        local project_dir, venv_path = utils.get_project_paths(filepath)
        local project_type = utils.detect_project_type(project_dir)
        local project_rel = vim.fn.fnamemodify(project_dir, ":~:.")
        
        -- Load the file as JSON so user can at least see it
        vim.cmd("edit " .. filepath)
        vim.bo.filetype = "json"
        
        -- Show clear instructions
        vim.notify(
            string.format("📓 Notebook requires jupytext to view properly"),
            vim.log.levels.WARN
        )
        vim.notify(
            string.format("📍 Project: %s (%s)", project_rel, project_type),
            vim.log.levels.INFO
        )
        
        if vim.fn.isdirectory(venv_path) == 0 then
            vim.notify(
                string.format("🔧 Run :PyworksSetup to create venv and install jupytext"),
                vim.log.levels.INFO
            )
        else
            vim.notify(
                string.format("🔧 Run: %s/bin/pip install jupytext", venv_path),
                vim.log.levels.INFO
            )
        end
        
        return false
    end
    
    return true
end

return M