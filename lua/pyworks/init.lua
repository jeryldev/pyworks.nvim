-- pyworks.nvim - Python environments tailored for Neovim
-- Main module

local M = {}
local config = require("pyworks.config")

-- Setup function
function M.setup(opts)
	
	-- Setup jupytext metadata fixing
	require("pyworks.jupytext-init").setup()
	
	-- Validate and setup configuration
	if opts then
		local ok, errors = config.validate_config(opts)
		if not ok then
			vim.notify("pyworks.nvim: Invalid configuration:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
			return
		end
	end

	-- Setup configuration
	M.config = config.setup(opts)

	-- Load submodules
	require("pyworks.commands").setup()
	require("pyworks.autocmds").setup(M.config)
	require("pyworks.cell-navigation").setup()

	-- Create user commands
	require("pyworks.commands").create_commands()

	-- Mark setup as complete
	config.set_state("setup_completed", true)
end

-- Expose config for backward compatibility
function M.get_config()
	return config.current
end

return M
