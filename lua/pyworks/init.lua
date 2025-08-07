-- pyworks.nvim - Zero-config multi-language support for Python, Julia, and R
-- Version: 3.0.0
--
-- Features:
-- - Automatic environment setup for Python, Julia, and R
-- - Smart package detection and installation
-- - Jupyter notebook support with automatic kernel management
-- - Zero configuration required - just open files and start working

local M = {}

-- Default configuration
local default_config = {
	python = {
		use_uv = false,
		preferred_venv_name = ".venv",
		auto_install_essentials = true,
		essentials = { "pynvim", "ipykernel", "jupyter_client", "jupytext" },
	},
	julia = {
		auto_install_ijulia = true,
	},
	r = {
		auto_install_irkernel = true,
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

-- Setup function
function M.setup(opts)
	-- Prevent multiple setup calls
	if vim.g.pyworks_setup_complete then
		return
	end
	
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
	
	-- Initialize state
	local state = require("pyworks.core.state")
	state.start_session()
	
	-- Set Python host if not already set
	if not vim.g.python3_host_prog then
		M.setup_python_host()
	end
	
	-- Mark setup as complete
	vim.g.pyworks_setup_complete = true
end

-- Setup Python host
function M.setup_python_host()
	-- Try to find the best Python executable
	local python_candidates = {
		vim.fn.getcwd() .. "/.venv/bin/python3",
		vim.fn.getcwd() .. "/.venv/bin/python",
		vim.fn.exepath("python3"),
		vim.fn.exepath("python"),
	}
	
	for _, python_path in ipairs(python_candidates) do
		if vim.fn.executable(python_path) == 1 then
			vim.g.python3_host_prog = python_path
			break
		end
	end
end

-- Manual commands (for power users)
-- These are optional - the plugin works without them

-- Command to manually trigger environment setup
vim.api.nvim_create_user_command("PyworksSetup", function()
	local detector = require("pyworks.core.detector")
	local filepath = vim.api.nvim_buf_get_name(0)
	detector.on_file_open(filepath)
end, {
	desc = "Manually trigger Pyworks environment setup for current file",
})

-- Command to install missing packages
vim.api.nvim_create_user_command("PyworksInstall", function()
	local ft = vim.bo.filetype
	if ft == "python" then
		local python = require("pyworks.languages.python")
		python.install_missing_packages()
	elseif ft == "julia" then
		local julia = require("pyworks.languages.julia")
		julia.install_missing_packages()
	elseif ft == "r" then
		local r = require("pyworks.languages.r")
		r.install_missing_packages()
	else
		vim.notify("No missing packages detected for this file type", vim.log.levels.INFO)
	end
end, {
	desc = "Install missing packages for current file",
})

-- Command to show package status
vim.api.nvim_create_user_command("PyworksStatus", function()
	local packages = require("pyworks.core.packages")
	local ft = vim.bo.filetype
	local language = nil
	
	if ft == "python" then
		language = "python"
	elseif ft == "julia" then
		language = "julia"
	elseif ft == "r" then
		language = "r"
	end
	
	if language then
		local result = packages.analyze_buffer(language)
		
		vim.notify(string.format(
			"[%s] Imports: %d | Installed: %d | Missing: %d",
			language:gsub("^%l", string.upper),
			#result.imports,
			#result.installed,
			#result.missing
		), vim.log.levels.INFO)
		
		if #result.missing > 0 then
			vim.notify(
				"Missing packages: " .. table.concat(result.missing, ", "),
				vim.log.levels.WARN
			)
		end
	else
		vim.notify("Pyworks: Not a supported file type", vim.log.levels.INFO)
	end
end, {
	desc = "Show package status for current file",
})

-- Command to clear cache
vim.api.nvim_create_user_command("PyworksClearCache", function()
	local cache = require("pyworks.core.cache")
	cache.clear()
	vim.notify("Pyworks cache cleared", vim.log.levels.INFO)
end, {
	desc = "Clear Pyworks cache",
})

-- Command to show cache statistics
vim.api.nvim_create_user_command("PyworksCacheStats", function()
	local cache = require("pyworks.core.cache")
	local stats = cache.stats()
	vim.notify(string.format(
		"Cache: %d total | %d active | %d expired",
		stats.total,
		stats.active,
		stats.expired
	), vim.log.levels.INFO)
end, {
	desc = "Show Pyworks cache statistics",
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
			"Will be created automatically when you open a Python file"
		})
	end
	
	-- Check Julia
	local julia = require("pyworks.languages.julia")
	if julia.has_julia() then
		health.ok("Julia installation found")
		if julia.has_ijulia() then
			health.ok("IJulia kernel installed")
		else
			health.warn("IJulia kernel not installed", {
				"Will be prompted to install when you open a Julia notebook"
			})
		end
	else
		health.warn("Julia not found", {
			"Install Julia from https://julialang.org"
		})
	end
	
	-- Check R
	local r = require("pyworks.languages.r")
	if r.has_r() then
		health.ok("R installation found")
		if r.has_irkernel() then
			health.ok("IRkernel installed")
		else
			health.warn("IRkernel not installed", {
				"Will be prompted to install when you open an R notebook"
			})
		end
	else
		health.warn("R not found", {
			"Install R from https://www.r-project.org"
		})
	end
	
	-- Check jupytext
	local jupytext = require("pyworks.notebook.jupytext")
	if jupytext.is_jupytext_installed() then
		health.ok("Jupytext installed")
	else
		health.warn("Jupytext not installed", {
			"Will be prompted to install when you open a notebook"
		})
	end
end

return M