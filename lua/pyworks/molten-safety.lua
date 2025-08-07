-- Safety wrapper for Molten to prevent hangs
local M = {}

-- Check if Molten is safe to use
function M.is_molten_safe()
	-- Check if we're in the middle of installing
	if vim.g.pyworks_needs_restart then
		return false
	end
	
	-- Check if Molten command exists
	if vim.fn.exists(":MoltenInit") ~= 2 then
		return false
	end
	
	-- Check if there was a previous error
	if vim.g.molten_error_detected then
		return false
	end
	
	-- Check if remote plugins are loaded
	local rplugin_file = vim.fn.stdpath("data") .. "/rplugin.vim"
	if vim.fn.filereadable(rplugin_file) == 0 then
		return false
	end
	
	return true
end

-- Safe wrapper for MoltenInit
function M.safe_molten_init(kernel)
	if not M.is_molten_safe() then
		return false
	end
	
	-- Try to call MoltenInit with error handling
	local ok = pcall(vim.cmd, "MoltenInit " .. (kernel or ""))
	
	if not ok then
		vim.g.molten_error_detected = true
		return false
	end
	
	return true
end

-- Disable Molten temporarily
function M.disable_molten()
	vim.g.molten_error_detected = true
	local utils = require("pyworks.utils")
	utils.notify("Molten has been temporarily disabled due to errors", vim.log.levels.WARN)
	utils.notify("Run :PyworksFixMolten to attempt to fix it", vim.log.levels.INFO)
end

return M