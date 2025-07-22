-- pyworks.nvim - Python environments tailored for Neovim
-- Main module

local M = {}

-- Default configuration
M.config = {
	-- Python settings
	python = {
		preferred_venv_name = ".venv",
		use_uv = true, -- Prefer uv over pip/venv when available
	},
	-- UI settings
	ui = {
		icons = {
			python = "🐍",
			success = "✓",
			error = "✗",
			warning = "⚠️",
			info = "ℹ",
		},
	},
	-- Auto-activation in terminal
	auto_activate_venv = true,
	-- Create .nvim.lua for notebook projects
	create_nvim_lua = {
		data_science = true,
		web = false,
		general = false,
		automation = false,
	},
}

-- Setup function
function M.setup(opts)
	-- Merge user config with defaults
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Load submodules
	require("pyworks.commands").setup()
	require("pyworks.autocmds").setup(M.config)
	require("pyworks.cell-navigation").setup()

	-- Create user commands
	require("pyworks.commands").create_commands()

	-- Mark setup as complete
	vim.g.pyworks_setup_complete = true
end

return M
