-- Health check for pyworks.nvim
-- Run with :checkhealth pyworks

local M = {}

function M.check()
	local health = vim.health or require("health")

	health.start("Pyworks Core")

	-- Check if plugin is loaded
	if vim.g.loaded_pyworks then
		health.ok("Plugin loaded")
	else
		health.error("Plugin not loaded", {
			"Ensure pyworks is in your runtimepath",
			"Try running :lua require('pyworks').setup()",
		})
		return
	end

	-- Check core modules
	local core_modules = {
		"pyworks.core.detector",
		"pyworks.core.cache",
		"pyworks.core.notifications",
		"pyworks.core.state",
		"pyworks.core.packages",
	}

	for _, module in ipairs(core_modules) do
		local ok, _ = pcall(require, module)
		if ok then
			health.ok(string.format("Module %s loaded", module))
		else
			health.error(string.format("Failed to load %s", module))
		end
	end

	-- Check plugin dependencies
	health.start("Plugin Dependencies")

	local dependencies = require("pyworks.dependencies")
	local dep_health = dependencies.check_health()
	for _, status in ipairs(dep_health) do
		if status:match("^✅") then
			health.ok(status:gsub("^✅ ", ""))
		else
			health.error(status:gsub("^❌ ", ""), {
				"Run :PyworksDiagnostics for detailed status",
				"Or manually install the missing dependency",
			})
		end
	end

	health.start("Language Support")

	-- Check Python
	local python = require("pyworks.languages.python")
	if vim.fn.executable("python3") == 1 or vim.fn.executable("python") == 1 then
		health.ok("Python executable found")

		if python.has_venv() then
			health.ok("Python virtual environment found at .venv")

			-- Check essential packages
			local essentials = { "pynvim", "ipykernel", "jupyter_client" }
			for _, pkg in ipairs(essentials) do
				if python.is_package_installed(pkg) then
					health.ok(string.format("Essential package '%s' installed", pkg))
				else
					health.warn(string.format("Essential package '%s' not installed", pkg), {
						"Will be installed automatically when needed",
					})
				end
			end
		else
			health.info("No Python virtual environment found", {
				"Will be created automatically when you open a Python file",
			})
		end
	else
		health.warn("Python not found", {
			"Install Python 3.8 or later",
			"Visit https://www.python.org/downloads/",
		})
	end

	health.start("Notebook Support")

	-- Check jupytext
	local jupytext = require("pyworks.notebook.jupytext")
	if jupytext.is_jupytext_installed() then
		health.ok("Jupytext installed (notebook viewer)")
	else
		health.info("Jupytext not installed", {
			"Will prompt to install when you open a .ipynb file",
			"Or install manually with: pip install jupytext",
		})
	end

	health.start("Configuration")

	-- Check if setup was called
	if vim.g.pyworks_setup_complete then
		health.ok("Setup completed")
	else
		health.warn("Setup not called", {
			"Add to your config: require('pyworks').setup()",
		})
	end

	-- Check Python host
	if vim.g.python3_host_prog then
		health.ok(string.format("Python host set to: %s", vim.g.python3_host_prog))

		-- Verify it works
		local check_cmd = vim.g.python3_host_prog .. " --version 2>&1"
		local result = vim.fn.system(check_cmd)
		if vim.v.shell_error == 0 then
			local version = result:match("Python (%d+%.%d+%.%d+)")
			if version then
				health.ok(string.format("Python host version: %s", version))
			end
		else
			health.error("Python host not working", {
				"Check that the path is correct",
				"Try unsetting vim.g.python3_host_prog",
			})
		end
	else
		health.info("Python host not explicitly set", {
			"Neovim will search for Python automatically",
		})
	end

	health.start("Performance")

	-- Check cache
	local cache = require("pyworks.core.cache")
	local stats = cache.stats()
	health.info(
		string.format("Cache stats: %d entries (%d active, %d expired)", stats.total, stats.active, stats.expired)
	)

	-- Check state
	local state = require("pyworks.core.state")
	local session_duration = state.get_session_duration()
	if session_duration > 0 then
		health.info(string.format("Session duration: %d seconds", session_duration))
	end

	health.start("File Type Detection")

	-- Check if autocmds are set up
	local autocmds = vim.api.nvim_get_autocmds({
		group = "Pyworks",
	})

	if #autocmds > 0 then
		health.ok(string.format("Found %d Pyworks autocmds", #autocmds))
	else
		health.warn("No Pyworks autocmds found", {
			"File detection may not work automatically",
			"Check that plugin/pyworks.lua is loaded",
		})
	end

	health.start("Keymaps")

	-- Check for leader key
	local leader = vim.g.mapleader or "\\"
	health.info(string.format("Leader key is: %s", leader))
	health.info(string.format("Package install keymap: %spi", leader))
end

return M
