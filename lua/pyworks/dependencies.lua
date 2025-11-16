-- Automatic dependency management for pyworks.nvim
-- Ensures all required plugins are installed and configured without user intervention

local M = {}

-- Check if a plugin is installed via lazy.nvim
local function is_plugin_installed(plugin_name)
	local lazy_ok, lazy = pcall(require, "lazy.core.config")
	if lazy_ok and lazy.plugins and lazy.plugins[plugin_name] then
		return true
	end
	return false
end

-- Comprehensive dependency check and auto-fix
function M.ensure_dependencies()
	local issues = {}
	local actions_taken = {}
	local needs_restart = false

	-- Define all required dependencies and their checks
	local dependencies = {
		{
			name = "molten-nvim",
			check = function()
				if not is_plugin_installed("molten-nvim") then
					return false, "not installed"
				end
				if vim.fn.exists(":MoltenInit") ~= 2 then
					return false, "not registered"
				end
				return true
			end,
			fix = function()
				if not is_plugin_installed("molten-nvim") then
					table.insert(issues, "Molten not installed")
					return false
				end
				if vim.fn.exists(":MoltenInit") ~= 2 then
					if M.register_molten() then
						table.insert(actions_taken, "Molten: Registered (restart required)")
						needs_restart = true
						return true
					else
						table.insert(issues, "Molten registration failed")
						return false
					end
				end
				return true
			end,
		},
		{
			name = "jupytext.nvim",
			check = function()
				if not is_plugin_installed("jupytext.nvim") then
					return false, "not installed"
				end
				local ok = pcall(require, "jupytext")
				if not ok then
					return false, "not configured"
				end
				-- Check if jupytext CLI is available
				local handle = io.popen("which jupytext 2>&1")
				if handle then
					local result = handle:read("*a")
					handle:close()
					if result == "" or result:match("not found") then
						return false, "CLI not found"
					end
				end
				return true
			end,
			fix = function()
				if not is_plugin_installed("jupytext.nvim") then
					table.insert(issues, "Jupytext not installed")
					return false
				end
				-- Try to configure if not already done
				local ok = pcall(require, "jupytext")
				if ok then
					local jup = require("jupytext")
					if jup.setup then
						pcall(jup.setup, {})
						table.insert(actions_taken, "Jupytext: Configured for .ipynb files")
					end
				end
				-- Check for jupytext CLI
				local python_cmd = vim.g.python3_host_prog or "python3"
				local handle = io.popen(python_cmd .. " -m pip show jupytext 2>&1")
				if handle then
					local result = handle:read("*a")
					handle:close()
					if result:match("not found") or result:match("No module") then
						-- Will be installed by pyworks' essential packages
						table.insert(actions_taken, "Jupytext CLI: Will auto-install with Python packages")
					end
				end
				return true
			end,
		},
		{
			name = "image.nvim",
			check = function()
				if not is_plugin_installed("image.nvim") then
					return false, "not installed"
				end
				local ok, img = pcall(require, "image")
				if not ok then
					return false, "not configured"
				end
				-- Check if it's actually initialized
				if not img.state or not img.state.backend then
					return false, "not initialized"
				end
				return true
			end,
			fix = function()
				if not is_plugin_installed("image.nvim") then
					table.insert(issues, "Image.nvim not installed")
					return false
				end
				-- Try to configure if not already done
				local ok, img = pcall(require, "image")
				if ok and img.setup then
					-- Detect terminal capabilities
					local backend = "kitty"
					local term = vim.env.TERM or ""
					local term_program = vim.env.TERM_PROGRAM or ""

					if term_program:match("kitty") or term_program:match("ghostty") then
						backend = "kitty"
					elseif term:match("xterm") or vim.env.DISPLAY then
						backend = "ueberzug" -- For X11 environments
					end

					local setup_ok = pcall(img.setup, {
						backend = backend,
						integrations = {
							markdown = {
								enabled = true,
								clear_in_insert_mode = false,
								download_remote_images = true,
								only_render_image_at_cursor = false,
								filetypes = { "markdown", "vimwiki" },
							},
						},
						max_width = nil,
						max_height = nil,
						max_width_window_percentage = nil,
						max_height_window_percentage = 50,
						window_overlap_clear_enabled = true,
						window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
					})

					if setup_ok then
						table.insert(actions_taken, string.format("Image.nvim: Configured with %s backend", backend))
					else
						table.insert(actions_taken, "Image.nvim: Configuration attempted")
					end
				end
				return true
			end,
		},
	}

	-- Check all dependencies
	local all_ok = true
	for _, dep in ipairs(dependencies) do
		local ok, issue = dep.check()
		if not ok then
			all_ok = false
			-- Try to fix automatically
			dep.fix()
		end
	end

	-- Report status with separated notifications for clarity
	if #issues > 0 then
		-- Critical issues that need manual intervention
		local msg = string.format(
			"⚠️  Pyworks: Missing dependencies - %s\nRun :Lazy sync to install",
			table.concat(issues, ", ")
		)
		vim.notify(msg, vim.log.levels.ERROR)
	elseif #actions_taken > 0 then
		-- Show what was configured
		local msg = "🔧 Pyworks: Configuring notebook environment\n• " .. table.concat(actions_taken, "\n• ")
		vim.notify(msg, vim.log.levels.INFO)

		-- Separate notification for restart if needed
		if needs_restart then
			vim.defer_fn(function()
				local restart_msg = "⚠️  One-time setup: Please restart Neovim to activate Molten\n"
					.. "   This is only needed once after initial installation"
				vim.notify(restart_msg, vim.log.levels.WARN)
			end, 200)
		end
	end
	-- Silent when everything is working (no notification)

	return all_ok
end

-- Register Molten remote plugin
function M.register_molten()
	-- Use the Python host that pyworks has configured
	local python_cmd = vim.g.python3_host_prog or "python3"

	-- Check if pynvim is available
	local handle = io.popen(python_cmd .. " -c 'import pynvim' 2>&1")
	if handle then
		local result = handle:read("*a")
		handle:close()

		if result == "" then -- pynvim is installed
			-- Check if we've already attempted registration this session
			if not vim.g.pyworks_molten_registration_attempted then
				vim.g.pyworks_molten_registration_attempted = true

				vim.schedule(function()
					-- Run UpdateRemotePlugins
					local success, err = pcall(vim.cmd, "UpdateRemotePlugins")

					if not success then
						vim.notify("❌ Failed to register Molten: " .. tostring(err), vim.log.levels.ERROR)
						return false
					end
				end)
				return true
			end
		else
			-- pynvim not installed - will be handled by pyworks essentials
			return false
		end
	end
	return false
end

-- Health check for dependencies
function M.check_health()
	local health = {}

	-- Check each plugin
	local plugins = {
		["molten-nvim"] = vim.fn.exists(":MoltenInit") == 2,
		["jupytext.nvim"] = pcall(require, "jupytext"),
		["image.nvim"] = pcall(require, "image"),
	}

	for plugin, is_ok in pairs(plugins) do
		if is_ok then
			table.insert(health, string.format("✅ %s: Installed and loaded", plugin))
		else
			table.insert(health, string.format("❌ %s: Not available", plugin))
		end
	end

	-- Check Python dependencies
	local python_cmd = vim.g.python3_host_prog or "python3"
	local python_deps = { "pynvim", "jupyter_client", "ipykernel", "jupytext" }
	for _, dep in ipairs(python_deps) do
		local handle = io.popen(string.format("%s -c 'import %s' 2>&1", python_cmd, dep))
		if handle then
			local result = handle:read("*a")
			handle:close()
			if result == "" then
				table.insert(health, string.format("✅ Python %s: Installed", dep))
			else
				table.insert(health, string.format("❌ Python %s: Not installed", dep))
			end
		end
	end

	-- Check jupytext CLI
	local handle = io.popen("which jupytext 2>&1")
	if handle then
		local result = handle:read("*a")
		handle:close()
		if result ~= "" and not result:match("not found") then
			table.insert(health, "✅ Jupytext CLI: Available in PATH")
		else
			table.insert(health, "❌ Jupytext CLI: Not found in PATH")
		end
	end

	return health
end

-- Setup function to be called from init.lua
function M.setup(opts)
	opts = opts or {}

	-- Defer dependency check to ensure lazy.nvim is loaded
	vim.defer_fn(function()
		M.ensure_dependencies()
	end, 100)
end

-- Manual command to check and fix dependencies
function M.install_dependencies()
	local all_ok = M.ensure_dependencies()
	if all_ok then
		vim.notify("✅ Pyworks: All dependencies are properly configured!", vim.log.levels.INFO)
	end
end

return M
