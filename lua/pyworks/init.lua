-- pyworks.nvim - Zero-config Python notebook support
-- Version: 3.0.0
--
-- Features:
-- - Automatic environment setup for Python
-- - Smart package detection and installation
-- - Jupyter notebook support with automatic kernel management
-- - Zero configuration required - just open files and start working

local M = {}

-- Constants
local PLUGIN_LOAD_DELAY_MS = 100 -- Delay to ensure plugins are loaded before configuration
local POST_SETUP_DELAY_MS = 500 -- Delay after environment setup before detection

-- Dependencies
local dependencies = require("pyworks.dependencies")
local error_handler = require("pyworks.core.error_handler")

-- Default configuration
local default_config = {
	python = {
		use_uv = false,
		preferred_venv_name = ".venv",
		auto_install_essentials = true,
		essentials = { "pynvim", "ipykernel", "jupyter_client", "jupytext", "numpy", "pandas", "matplotlib" },
	},
	cache = {
		-- Cache TTL overrides (in seconds)
		kernel_list = 60,
		installed_packages = 300,
	},
	notifications = {
		verbose_first_time = true,
		silent_when_ready = true,
		show_progress = true,
		debug_mode = false,
	},
	auto_detect = true, -- Automatically detect and setup on file open
}

-- Plugin configuration
local config = {}

-- Validate user config types (warns but doesn't crash)
local function validate_config(user_opts)
	if not user_opts or type(user_opts) ~= "table" then
		return
	end

	local warnings = {}

	-- Check python config
	if user_opts.python then
		if user_opts.python.use_uv ~= nil and type(user_opts.python.use_uv) ~= "boolean" then
			table.insert(warnings, "python.use_uv should be boolean")
		end
		if
			user_opts.python.auto_install_essentials ~= nil
			and type(user_opts.python.auto_install_essentials) ~= "boolean"
		then
			table.insert(warnings, "python.auto_install_essentials should be boolean")
		end
		if user_opts.python.essentials ~= nil and type(user_opts.python.essentials) ~= "table" then
			table.insert(warnings, "python.essentials should be a table/array")
		end
	end

	-- Check notifications config
	if user_opts.notifications then
		if user_opts.notifications.debug_mode ~= nil and type(user_opts.notifications.debug_mode) ~= "boolean" then
			table.insert(warnings, "notifications.debug_mode should be boolean")
		end
	end

	-- Check cache config
	if user_opts.cache then
		for key, value in pairs(user_opts.cache) do
			if type(value) ~= "number" then
				table.insert(warnings, string.format("cache.%s should be number (seconds)", key))
			end
		end
	end

	-- Report warnings
	if #warnings > 0 then
		vim.notify("[Pyworks] Config warnings:\n• " .. table.concat(warnings, "\n• "), vim.log.levels.WARN)
	end
end

-- Auto-configure external dependencies with proven settings
function M.configure_dependencies(opts)
	opts = opts or {}

	-- Configure Molten with optimal settings (only if molten is available)
	if not opts.skip_molten and vim.fn.exists(":MoltenInit") == 2 then
		vim.g.molten_image_provider = "image.nvim"
		vim.g.molten_auto_open_output = true
		vim.g.molten_virt_text_output = true
		vim.g.molten_virt_lines_off_by_1 = false
		vim.g.molten_output_win_max_height = 40
		vim.g.molten_output_win_max_width = 150
		vim.g.molten_output_crop_border = true
		vim.g.molten_wrap_output = true
		vim.g.molten_output_show_more = true
		vim.g.molten_output_win_border = "rounded"
		vim.g.molten_auto_open_html_in_browser = false
		vim.g.molten_auto_image_popup = false
		vim.g.molten_tick_rate = 100
	end

	-- Configure jupytext with automatic fallback handling
	-- If jupytext CLI is not available, sets up a graceful fallback that shows
	-- notebooks as read-only JSON with helpful messages
	if not opts.skip_jupytext then
		local jupytext_module = require("pyworks.notebook.jupytext")
		jupytext_module.configure_jupytext_nvim()
	end

	-- Configure image.nvim with optimal settings
	if not opts.skip_image then
		local ok, image = pcall(require, "image")
		if ok then
			local backend = opts.image_backend or "kitty" -- Default to kitty
			image.setup({
				backend = backend,
				integrations = {
					markdown = {
						enabled = true,
						clear_in_insert_mode = false,
						download_remote_images = true,
						only_render_image_at_cursor = false,
						filetypes = { "markdown", "vimwiki" },
					},
					html = { enabled = false },
					css = { enabled = false },
				},
				max_width = 150,
				max_height = 40,
				max_height_window_percentage = math.huge,
				max_width_window_percentage = math.huge,
				window_overlap_clear_enabled = true,
				window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
				editor_only_render_when_focused = false,
				tmux_show_only_in_active_window = false,
			})
		end
	end
end

-- Setup function
function M.setup(opts)
	-- Prevent multiple setup calls
	if vim.g.pyworks_setup_complete then
		return
	end

	-- Ensure all dependencies are installed and configured
	-- This handles molten-nvim, jupytext.nvim, image.nvim automatically
	dependencies.setup(opts)

	-- Auto-configure dependencies with proven settings
	-- Use defer_fn to ensure plugins are loaded
	vim.defer_fn(function()
		M.configure_dependencies(opts)
	end, PLUGIN_LOAD_DELAY_MS)

	-- Add helpful keymaps
	if not opts.skip_keymaps then
		vim.keymap.set("n", "<leader>ps", "<cmd>PyworksStatus<cr>", { desc = "Pyworks: Show status" })
	end

	-- Validate user config before merging (warns on type mismatches)
	validate_config(opts)

	-- Merge user configuration with defaults
	config = vim.tbl_deep_extend("force", default_config, opts or {})

	-- Configure core modules
	local cache = require("pyworks.core.cache")
	cache.configure(config.cache)

	local notifications = require("pyworks.core.notifications")
	notifications.configure(config.notifications)

	-- Configure language modules
	local python = require("pyworks.languages.python")
	python.configure(config.python)

	-- Initialize state (load persistent data, then start session)
	local state = require("pyworks.core.state")
	state.init()
	state.start_session()

	-- Set Python host if not already set
	if not vim.g.python3_host_prog then
		python.setup_python_host()
	end

	-- Mark setup as complete
	vim.g.pyworks_setup_complete = true

	-- Load notebook creation commands
	require("pyworks.commands.create")
end

-- Manual commands (for power users)
-- These are optional - the plugin works without them

-- Command to manually trigger environment setup
vim.api.nvim_create_user_command("PyworksSetup", function()
	local filepath = vim.api.nvim_buf_get_name(0)

	-- If no file is open, use cwd as the project directory
	if filepath == "" then
		local cwd = vim.fn.getcwd()
		vim.notify("📁 Setting up Python environment in: " .. cwd, vim.log.levels.INFO)

		-- Create venv in cwd
		local python = require("pyworks.languages.python")
		local utils = require("pyworks.utils")

		-- Use a dummy filepath in cwd to get project paths
		local dummy_filepath = cwd .. "/setup.py"
		local ok = error_handler.protected_call(python.ensure_environment, "Setup failed", dummy_filepath)
		if ok then
			vim.notify("✅ Python environment setup complete", vim.log.levels.INFO)
			vim.notify("💡 You can now create notebooks with :PyworksNewPythonNotebook", vim.log.levels.INFO)
		end
		return
	end

	-- Validate filepath
	filepath = error_handler.validate_filepath(filepath, "setup environment")
	if not filepath then
		return
	end

	-- Determine file type and run appropriate setup
	local ext = vim.fn.fnamemodify(filepath, ":e")
	local ft = vim.bo.filetype

	if ext == "py" or ft == "python" or ext == "ipynb" then
		local python = require("pyworks.languages.python")
		local ok = error_handler.protected_call(python.ensure_environment, "Setup failed", filepath)
		if ok then
			vim.notify("✅ Python environment setup complete", vim.log.levels.INFO)
			vim.defer_fn(function()
				local detector = require("pyworks.core.detector")
				detector.on_file_open(filepath)
			end, POST_SETUP_DELAY_MS)
		end
	else
		vim.notify("ℹ️ Pyworks only supports Python files", vim.log.levels.INFO)
	end
end, {
	desc = "Manually trigger Pyworks environment setup for current file or cwd",
})

-- Command to sync (install missing) packages
vim.api.nvim_create_user_command("PyworksSync", function()
	local ft = vim.bo.filetype
	if ft == "python" then
		local python = require("pyworks.languages.python")
		error_handler.protected_call(python.install_missing_packages, "Package sync failed")
	else
		vim.notify("Pyworks only supports Python files", vim.log.levels.INFO)
	end
end, {
	desc = "Sync packages - install missing packages detected from imports",
})

-- Command to show package status
vim.api.nvim_create_user_command("PyworksStatus", function()
	local packages = require("pyworks.core.packages")
	local ft = vim.bo.filetype

	if ft == "python" then
		local result = packages.analyze_buffer("python")

		vim.notify(
			string.format(
				"[Python] Imports: %d | Installed: %d | Missing: %d",
				#result.imports,
				#result.installed,
				#result.missing
			),
			vim.log.levels.INFO
		)

		if #result.missing > 0 then
			vim.notify("Missing packages: " .. table.concat(result.missing, ", "), vim.log.levels.WARN)
		end
	else
		vim.notify("Pyworks: Not a Python file", vim.log.levels.INFO)
	end
end, {
	desc = "Show package status for current file",
})

-- Package management commands
vim.api.nvim_create_user_command("PyworksAdd", function(opts)
	local python = require("pyworks.languages.python")
	if opts.args and opts.args ~= "" then
		python.install_python_packages(opts.args)
	else
		vim.ui.input({ prompt = "Packages to add (space/comma separated): " }, function(input)
			if input and input ~= "" then
				python.install_python_packages(input)
			end
		end)
	end
end, {
	nargs = "*",
	desc = "Add packages to project virtual environment",
	complete = function()
		return { "numpy", "pandas", "matplotlib", "requests", "pytest", "black", "flake8", "mypy" }
	end,
})

vim.api.nvim_create_user_command("PyworksRemove", function(opts)
	local python = require("pyworks.languages.python")
	if opts.args and opts.args ~= "" then
		python.uninstall_python_packages(opts.args)
	else
		vim.ui.input({ prompt = "Packages to remove (space/comma separated): " }, function(input)
			if input and input ~= "" then
				python.uninstall_python_packages(input)
			end
		end)
	end
end, {
	nargs = "*",
	desc = "Remove packages from project virtual environment",
})

vim.api.nvim_create_user_command("PyworksList", function()
	local python = require("pyworks.languages.python")
	python.list_python_packages()
end, {
	desc = "List installed packages in project virtual environment",
})

vim.api.nvim_create_user_command("PyworksHelp", function()
	local help = {
		"=== Pyworks Commands ===",
		"",
		"NOTEBOOK CREATION",
		"  :PyworksNewPython [name]         Create Python file with cell markers",
		"  :PyworksNewPythonNotebook [name] Create Jupyter notebook (.ipynb)",
		"",
		"ENVIRONMENT",
		"  :PyworksSetup                    Create venv and install essentials",
		"  :PyworksStatus                   Show package status (imports/installed/missing)",
		"  :PyworksDiagnostics              Run diagnostics (venv, plugins, cache)",
		"",
		"PACKAGE MANAGEMENT",
		"  :PyworksSync                     Install missing packages from imports",
		"  :PyworksAdd [packages]           Add packages to venv",
		"  :PyworksRemove [packages]        Remove packages from venv",
		"  :PyworksList                     List installed packages",
		"",
		"KEYMAPS",
		"  <leader>ps                       Show package status",
		"  <leader>jl                       Run current line",
		"  <leader>jc                       Run cell and move to next",
		"  <leader>je                       Re-run current cell",
		"",
		"For full documentation: :help pyworks",
	}

	vim.cmd("new")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, help)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.api.nvim_buf_set_name(buf, "Pyworks Help")
	vim.bo[buf].modifiable = false
end, {
	desc = "Show Pyworks commands and keymaps",
})

-- Export configuration for other modules
function M.get_config()
	return config
end

-- Health check function
function M.health()
	local health = vim.health or require("health")

	health.start("Pyworks")

	-- Check Python
	local python = require("pyworks.languages.python")
	if python.has_venv() then
		health.ok("Python virtual environment found")
	else
		health.warn("No Python virtual environment found", {
			"Will be created automatically when you open a Python file",
		})
	end

	-- Check jupytext
	local jupytext = require("pyworks.notebook.jupytext")
	if jupytext.is_jupytext_installed() then
		health.ok("Jupytext installed")
	else
		health.warn("Jupytext not installed", {
			"Will be prompted to install when you open a notebook",
		})
	end
end

return M
