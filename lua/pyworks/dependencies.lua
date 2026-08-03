-- Automatic dependency management for pyworks.nvim
-- Ensures all required plugins are installed and configured without user intervention

local M = {}

local utils = require("pyworks.utils")

-- Detect terminal backend for image rendering
-- Returns: backend name (string), is_supported (boolean), detection_info (string)
function M.detect_image_backend()
	local term = vim.env.TERM or ""
	local term_program = vim.env.TERM_PROGRAM or ""
	local kitty_window_id = vim.env.KITTY_WINDOW_ID
	local wezterm_pane = vim.env.WEZTERM_PANE
	local iterm_session = vim.env.ITERM_SESSION_ID
	local ghostty = vim.env.GHOSTTY_RESOURCES_DIR

	-- Check for kitty protocol support (highest priority)
	if kitty_window_id or term_program:lower():match("kitty") then
		return "kitty", true, "Detected Kitty terminal"
	end

	-- Check for Ghostty (uses kitty protocol)
	if ghostty or term_program:lower():match("ghostty") then
		return "kitty", true, "Detected Ghostty terminal (kitty protocol)"
	end

	-- Check for WezTerm (uses kitty protocol)
	if wezterm_pane or term_program:lower():match("wezterm") then
		return "kitty", true, "Detected WezTerm (kitty protocol)"
	end

	-- Check for iTerm2 (supports inline images)
	if iterm_session or term_program:lower():match("iterm") then
		return "kitty", true, "Detected iTerm2 (kitty protocol)"
	end

	-- Check for X11 environments (ueberzug)
	if vim.env.DISPLAY and vim.fn.executable("ueberzug") == 1 then
		return "ueberzug", true, "Detected X11 with ueberzug"
	end

	-- Check for tmux (may work with underlying terminal)
	if vim.env.TMUX then
		-- tmux passthrough may work if underlying terminal supports kitty
		return "kitty", false, "Running in tmux - image support may be limited"
	end

	-- No known protocol: say so rather than naming kitty, which callers used as
	-- the backend regardless of the false support flag, emitting escape
	-- sequences an unsupporting terminal renders as garbage
	return nil, false, "Unknown terminal - image rendering unavailable"
end

-- Which molten is actually installed?
--
-- pyworks declares jeryldev/molten-nvim in lazy.lua, but lazy resolves plugins
-- by name: a user who already had benlubas/molten-nvim keeps theirs, and then
-- runs without the fork's MoltenTick reentrancy guard and dict-iteration fix.
-- Pyworks cannot uninstall another plugin's spec, so the next best thing is to
-- notice and say so.

-- Is this a url for the fork pyworks ships? nil when there is nothing to judge.
function M.is_fork_url(url)
	if type(url) ~= "string" or url == "" then
		return nil
	end
	return url:lower():find("jeryldev/molten%-nvim") ~= nil
end

-- Does this molten checkout contain the reentrancy guard? nil if the file is
-- not there to read. Checked in addition to the url because a fork can be
-- installed under any remote name, and the behaviour is what matters.
function M.has_reentrancy_guard(molten_dir)
	if type(molten_dir) ~= "string" or molten_dir == "" then
		return nil
	end
	local init_py = molten_dir .. "/rplugin/python3/molten/__init__.py"
	if vim.fn.filereadable(init_py) ~= 1 then
		return nil
	end
	local ok, content = pcall(vim.fn.readfile, init_py)
	if not ok then
		return nil
	end
	for _, line in ipairs(content) do
		if line:find("_ticking", 1, true) then
			return true
		end
	end
	return false
end

-- Describe the installed molten: { installed, url, dir, is_fork, has_guard }
-- Whether Molten's repeating tick timer exists.
--
-- Molten notices a kernel became ready only inside MoltenBuffer.tick(), and
-- nothing calls that but the MoltenTick timer started at the end of Molten's
-- _initialize() - after canvas.init(). If image provider setup throws, Molten
-- is left half-initialised: :MoltenInit still reports success and the kernel
-- really does start, but nothing ever polls it, so no MoltenKernelReady is
-- ever emitted and every cell waits forever with no error (issue #10).
--
-- The absence of this timer separates "Molten never started a kernel" from
-- "Molten started one and is not watching it", which no other signal does.
function M.molten_tick_timer()
	-- vim.fn.string(vim.fn.timer_info()) does NOT work here: routing the list
	-- through Lua turns each callback into vim.NIL, losing the name. Evaluating
	-- string() in vimscript keeps the Funcref intact. The expression is a fixed
	-- literal with no interpolation - nothing here is caller-controlled.
	local ok, rendered = pcall(vim.fn.eval, "string(timer_info())")
	if not ok or type(rendered) ~= "string" then
		return { running = false, known = false }
	end

	return { running = rendered:find("MoltenTick", 1, true) ~= nil, known = true }
end

function M.molten_source()
	local info = { installed = false }

	local lazy_ok, lazy = pcall(require, "lazy.core.config")
	if lazy_ok and lazy.plugins then
		local spec = lazy.plugins["molten-nvim"]
		if spec then
			info.installed = true
			info.url = spec.url
			info.dir = spec.dir
		end
	end

	info.is_fork = M.is_fork_url(info.url)
	info.has_guard = M.has_reentrancy_guard(info.dir)

	-- The guard is the ground truth; the url only corroborates it
	if info.has_guard ~= nil then
		info.is_fork = info.has_guard
	end

	return info
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
				if not utils.is_plugin_installed("molten-nvim") then
					return false, "not installed"
				end
				if vim.fn.exists(":MoltenInit") ~= 2 then
					return false, "not registered"
				end
				return true
			end,
			fix = function()
				if not utils.is_plugin_installed("molten-nvim") then
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
			name = "jupytext CLI",
			check = function()
				-- Check if jupytext CLI is available
				if vim.fn.executable("jupytext") == 1 then
					return true
				end
				-- Resolve the venv from the file's project rather than cwd: editing a
				-- notebook outside the editor's working directory reported jupytext
				-- missing when it was installed (or the reverse)
				local _, venv_path = utils.get_project_paths(vim.api.nvim_buf_get_name(0))
				if vim.fn.executable(venv_path .. "/bin/jupytext") == 1 then
					return true
				end
				return false, "CLI not found"
			end,
			fix = function()
				-- jupytext CLI will be installed by pyworks' essential packages
				if vim.fn.executable("jupytext") ~= 1 then
					table.insert(actions_taken, "Jupytext CLI: Will auto-install with Python packages")
				end
				return true
			end,
		},
		{
			name = "image.nvim",
			check = function()
				if not utils.is_plugin_installed("image.nvim") then
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
				if not utils.is_plugin_installed("image.nvim") then
					table.insert(issues, "Image.nvim not installed")
					return false
				end
				-- Try to configure if not already done
				local ok, img = pcall(require, "image")
				if ok and img.setup then
					-- Use robust terminal detection
					local backend, is_supported, detection_info = M.detect_image_backend()

					local setup_ok, setup_err = pcall(img.setup, {
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
						window_overlap_clear_enabled = false,
						window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
					})

					if setup_ok then
						local status_msg = string.format("Image.nvim: %s (%s backend)", detection_info, backend)
						table.insert(actions_taken, status_msg)

						-- Warn if terminal support is uncertain
						if not is_supported then
							table.insert(
								issues,
								"Image rendering may not work in this terminal. Try Kitty, Ghostty, WezTerm, or iTerm2."
							)
						end
					else
						local err_msg = setup_err and tostring(setup_err) or "unknown error"
						table.insert(issues, string.format("Image.nvim setup failed: %s", err_msg))
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
		local msg =
			string.format("Pyworks: Missing dependencies - %s\nRun :Lazy sync to install", table.concat(issues, ", "))
		vim.notify(msg, vim.log.levels.ERROR)
	elseif #actions_taken > 0 and needs_restart then
		-- Only show configuration message if restart is needed (first-time setup)
		local msg = "Pyworks: Configuring notebook environment\n- " .. table.concat(actions_taken, "\n- ")
		vim.notify(msg, vim.log.levels.INFO)

		-- Separate notification for restart
		vim.defer_fn(function()
			local restart_msg = "One-time setup: Please restart Neovim to activate Molten\n"
				.. "   This is only needed once after initial installation"
			vim.notify(restart_msg, vim.log.levels.WARN)
		end, 200)
	end
	-- Silent when everything is working (no notification)

	return all_ok
end

-- Register Molten remote plugin
function M.register_molten()
	-- Use the Python host that pyworks has configured
	local python_cmd = vim.g.python3_host_prog or "python3"

	-- Check if pynvim is available using vim.system (Neovim 0.10+)
	local ok, result = pcall(function()
		return vim.system({ python_cmd, "-c", "import pynvim" }, { text = true }):wait()
	end)

	if not ok or not result or result.code ~= 0 then
		-- pynvim not installed - will be handled by pyworks essentials
		return false
	end

	-- pynvim is installed - check if we've already attempted registration this session
	if not vim.g.pyworks_molten_registration_attempted then
		vim.g.pyworks_molten_registration_attempted = true

		vim.schedule(function()
			-- Run UpdateRemotePlugins
			local success, err = pcall(vim.cmd, "UpdateRemotePlugins")

			if not success then
				vim.notify("Failed to register Molten: " .. tostring(err), vim.log.levels.ERROR)
			end
		end)
		return true
	end

	return false
end

-- Health check for dependencies
function M.check_health()
	local health = {}

	-- Check each plugin
	local plugins = {
		["molten-nvim"] = vim.fn.exists(":MoltenInit") == 2,
		["jupytext CLI"] = vim.fn.executable("jupytext") == 1,
		["image.nvim"] = pcall(require, "image"),
	}

	for plugin, is_ok in pairs(plugins) do
		if is_ok then
			table.insert(health, string.format("OK: %s: Installed and loaded", plugin))
		else
			table.insert(health, string.format("ERROR: %s: Not available", plugin))
		end
	end

	-- Check Python dependencies
	local python_deps = { "pynvim", "jupyter_client", "ipykernel", "jupytext" }
	for _, dep in ipairs(python_deps) do
		if utils.check_python_import(dep) then
			table.insert(health, string.format("OK: Python %s: Installed", dep))
		else
			table.insert(health, string.format("ERROR: Python %s: Not installed", dep))
		end
	end

	-- Check jupytext CLI using safe executable check
	if vim.fn.executable("jupytext") == 1 then
		table.insert(health, "OK: Jupytext CLI: Available in PATH")
	else
		table.insert(health, "ERROR: Jupytext CLI: Not found in PATH")
	end

	return health
end

-- Setup function to be called from init.lua
function M.setup(opts)
	vim.validate({ opts = { opts, "table", true } })
	opts = opts or {}

	-- Defer dependency check to ensure lazy.nvim is loaded
	vim.defer_fn(function()
		M.ensure_dependencies()
	end, 100)
end

return M
