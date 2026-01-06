-- Python language support for pyworks.nvim
-- Handles Python files and notebooks with Python kernels

local M = {}

local cache = require("pyworks.core.cache")
local error_handler = require("pyworks.core.error_handler")
local notifications = require("pyworks.core.notifications")
local state = require("pyworks.core.state")
local utils = require("pyworks.utils")

-- Lazy-loaded to avoid circular dependency with packages.lua
local function get_packages()
	return require("pyworks.core.packages")
end

-- Timeout constants (in milliseconds)
local IMPORT_CHECK_TIMEOUT_MS = 5000 -- 5 seconds for import check
local PIP_LIST_TIMEOUT_MS = 15000 -- 15 seconds for pip list
local VENV_CREATE_TIMEOUT_MS = 60000 -- 60 seconds for venv creation

-- Helper to get current buffer's filepath
local function get_current_filepath()
	local path = vim.fn.expand("%:p")
	return path ~= "" and path or nil
end

-- Configuration
local config = {
	use_uv = true, -- Prefer uv if available (much faster!)
	preferred_venv_name = ".venv",
	auto_install_essentials = true,
	essentials = {
		"pynvim",
		"ipykernel",
		"jupyter_client",
		"jupytext",
	},
}

-- Configure Python module
function M.configure(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Setup Python host for Neovim
-- Sets vim.g.python3_host_prog to the project's venv Python or system Python
function M.setup_python_host(filepath)
	local python_candidates = {}

	if filepath then
		local project_dir, venv_path = utils.get_project_paths(filepath)
		table.insert(python_candidates, venv_path .. "/bin/python3")
		table.insert(python_candidates, venv_path .. "/bin/python")
	else
		table.insert(python_candidates, vim.fn.getcwd() .. "/.venv/bin/python3")
		table.insert(python_candidates, vim.fn.getcwd() .. "/.venv/bin/python")
	end

	table.insert(python_candidates, vim.fn.exepath("python3"))
	table.insert(python_candidates, vim.fn.exepath("python"))

	for _, python_path in ipairs(python_candidates) do
		if vim.fn.executable(python_path) == 1 then
			if filepath then
				vim.b.python3_host_prog = python_path
				vim.g.python3_host_prog = python_path
			else
				vim.g.python3_host_prog = python_path
			end
			break
		end
	end
end

-- Check if virtual environment exists
-- Now accepts optional filepath to check venv for that file's project
function M.has_venv(filepath)
	local project_dir, venv_path = utils.get_project_paths(filepath)
	return vim.fn.isdirectory(venv_path) == 1
end

-- Get Python path
-- Now accepts optional filepath to get Python for that file's project
function M.get_python_path(filepath)
	if M.has_venv(filepath) then
		local project_dir, venv_path = utils.get_project_paths(filepath)
		return venv_path .. "/bin/python"
	end
	return nil
end

-- Get pip path
-- Now accepts optional filepath to get pip for that file's project
function M.get_pip_path(filepath)
	if M.has_venv(filepath) then
		local project_dir, venv_path = utils.get_project_paths(filepath)
		return venv_path .. "/bin/pip"
	end
	return nil
end

-- Check if venv uses uv
function M.venv_uses_uv(filepath)
	if not M.has_venv(filepath) then
		return false
	end

	local project_dir, venv_path = utils.get_project_paths(filepath)

	-- Primary check: uv.lock file in project (most reliable)
	if vim.fn.filereadable(project_dir .. "/uv.lock") == 1 then
		return true
	end

	-- Secondary check: Look for UV-specific markers in pyvenv.cfg
	-- UV venvs have specific comments added by uv
	local pyvenv_cfg = venv_path .. "/pyvenv.cfg"
	if vim.fn.filereadable(pyvenv_cfg) == 1 then
		local content = vim.fn.readfile(pyvenv_cfg)
		for _, line in ipairs(content) do
			-- Look for UV-specific comments or markers
			-- UV adds "uv = " lines to pyvenv.cfg
			if line:match("^uv = ") or line:match("^uv%-version = ") then
				return true
			end
		end
	end

	-- Tertiary check: Check if pip is missing (UV venvs don't have pip by default)
	local pip_path = venv_path .. "/bin/pip"
	if vim.fn.executable(pip_path) == 0 then
		-- No pip in venv is a strong indicator of UV
		return true
	end

	return false
end

-- Determine which package manager to use
function M.get_package_manager(filepath)
	if M.has_venv(filepath) then
		local project_dir, venv_path = utils.get_project_paths(filepath)
		-- If venv was created with uv, we need to use uv pip
		if M.venv_uses_uv(filepath) then
			-- uv pip needs to be called from outside venv
			if vim.fn.executable("uv") == 1 then
				return "uv pip"
			else
				-- Fallback to pip if uv not available
				return venv_path .. "/bin/pip"
			end
		else
			-- Regular pip venv - ALWAYS use the venv's pip
			-- Don't use UV for regular pip venvs even if UV is available
			return venv_path .. "/bin/pip"
		end
	else
		-- No venv yet, use configuration preference
		if config.use_uv and vim.fn.executable("uv") == 1 then
			return "uv" -- Will create venv with uv
		else
			return "pip"
		end
	end
end

-- Build pip/uv command with proper syntax
-- action: "install", "uninstall", "list"
-- packages: string of packages (for install/uninstall) or nil (for list)
-- filepath: file path to determine venv location
-- opts: { format = "freeze", quiet = true }
local function build_pip_command(action, packages, filepath, opts)
	opts = opts or {}
	local _, venv_path = utils.get_project_paths(filepath)
	local python_path = venv_path .. "/bin/python"
	local is_uv = M.venv_uses_uv(filepath) and vim.fn.executable("uv") == 1

	local cmd
	if is_uv then
		cmd = string.format("uv pip %s --python %s", action, vim.fn.shellescape(python_path))
	else
		local pip_path = M.get_pip_path(filepath)
		cmd = string.format("%s %s", pip_path, action)
	end

	if packages and packages ~= "" then
		cmd = cmd .. " " .. packages
	end

	if opts.format then
		cmd = cmd .. " --format=" .. opts.format
	end

	if opts.yes and not is_uv then
		cmd = cmd .. " -y"
	end

	if opts.quiet then
		cmd = cmd .. " 2>/dev/null"
	end

	return cmd, is_uv
end

-- Create virtual environment
function M.create_venv(filepath)
	filepath = filepath or get_current_filepath()
	if M.has_venv(filepath) then
		return true
	end

	local project_dir, venv_path = utils.get_project_paths(filepath)

	-- First check if uv is available globally
	local use_uv = vim.fn.executable("uv") == 1 -- Check for uv regardless of config

	local cmd
	if use_uv then
		-- Use uv for speed (it's very fast!)
		-- uv venv accepts full path
		cmd = string.format("uv venv %s", vim.fn.shellescape(venv_path))
	else
		-- Use standard venv with full path
		local python = vim.fn.executable("python3") == 1 and "python3" or "python"
		cmd = string.format("%s -m venv %s", python, vim.fn.shellescape(venv_path))
	end

	-- Execute command with timeout (no need to cd, using full paths)
	local success, result, _ = utils.system_with_timeout(cmd, VENV_CREATE_TIMEOUT_MS)

	if success then
		cache.invalidate("venv_check")
		state.set_env_status("python", "venv_created")
	else
		local error_msg = string.format("Failed to create venv. Command: %s, Error: %s", cmd, result or "unknown")
		notifications.notify_error(error_msg)
	end

	return success
end

-- Install essential packages
function M.install_essentials(filepath)
	filepath = filepath or get_current_filepath()

	-- Guard against duplicate calls (installation is async)
	local project_dir, venv_path = utils.get_project_paths(filepath)
	local install_key = state.KEYS.INSTALLING_ESSENTIALS .. (project_dir or "global")
	if state.get(install_key) then
		return true -- Already installing
	end

	if not M.has_venv(filepath) then
		if not M.create_venv(filepath) then
			return false
		end
	end

	-- Check if essentials are already installed
	local missing_essentials = {}
	for _, pkg in ipairs(config.essentials) do
		if not M.is_package_installed(pkg, filepath) then
			table.insert(missing_essentials, pkg)
		end
	end

	if #missing_essentials == 0 then
		return true
	end

	-- Mark as installing to prevent duplicate calls
	state.set(install_key, true)

	-- Get the correct package manager command
	local package_manager = M.get_package_manager(filepath)

	-- Check if we're using uv or pip
	local is_uv = package_manager:match("^uv")

	if is_uv then
		-- For uv, check that uv is available
		if vim.fn.executable("uv") == 0 then
			notifications.notify_error("uv not found but venv was created with uv")
			return false
		end
	else
		-- For pip, check that pip exists in venv
		local pip_path = M.get_pip_path()
		if not pip_path or vim.fn.executable(pip_path) == 0 then
			notifications.notify_error("pip not found in virtual environment")
			return false
		end
	end

	-- Upgrade pip if using pip (not needed for uv)
	if not is_uv then
		pcall(vim.system, { package_manager, "install", "--upgrade", "pip" }, { text = true })
	end

	local packages_str = table.concat(missing_essentials, " ")
	local cmd = build_pip_command("install", packages_str, filepath)

	if notifications.get_config().debug_mode then
		notifications.notify("[Debug] Running: " .. cmd, vim.log.levels.DEBUG)
	end

	-- Ensure project_dir is valid
	if not project_dir or vim.fn.isdirectory(project_dir) ~= 1 then
		notifications.notify_error("Invalid project directory for essentials: " .. (project_dir or "nil"))
		return false
	end

	-- vim.system requires a table; wrap string commands in shell invocation
	local cmd_table = type(cmd) == "string" and { "sh", "-c", cmd } or cmd

	local ok, sys_obj = pcall(vim.system, cmd_table, {
		text = true,
		cwd = project_dir,
	}, function(obj)
		vim.schedule(function()
			-- Clear the installing flag
			state.set(install_key, nil)

			if obj.code == 0 then
				for _, pkg in ipairs(missing_essentials) do
					state.mark_package_installed("python", pkg)
				end
				cache.invalidate("installed_packages_python")
			else
				local error_msg = "Failed to install essential packages."
				local stderr = obj.stderr or ""
				local filtered_errors = {}
				for line in stderr:gmatch("[^\r\n]+") do
					if
						not line:match("WARNING")
						and not line:match("Resolved")
						and not line:match("Installed")
						and not line:match("Collecting")
						and not line:match("Installing")
					then
						table.insert(filtered_errors, line)
					end
				end
				if #filtered_errors > 0 then
					error_msg = error_msg .. "\nError: " .. table.concat(filtered_errors, "\n")
				end
				notifications.notify_error(error_msg)
			end
		end)
	end)

	if not ok then
		state.set(install_key, nil) -- Clear the installing flag
		notifications.notify_error("Failed to start essential packages installation: " .. tostring(sys_obj))
		return false
	end

	return true
end

-- Check if a package is installed (with timeout to prevent UI blocking)
function M.is_package_installed(package_name, filepath)
	filepath = filepath or get_current_filepath()
	local python_path = M.get_python_path(filepath)
	if not python_path then
		return false
	end

	-- Use centralized reverse mapping to get import name from package name
	local import_name = get_packages().map_package_to_import(package_name, "python")

	-- Escape paths and import name for shell safety
	local cmd = string.format(
		"%s -c %s 2>/dev/null",
		vim.fn.shellescape(python_path),
		vim.fn.shellescape("import " .. import_name)
	)
	local success, _, _ = utils.system_with_timeout(cmd, IMPORT_CHECK_TIMEOUT_MS)
	return success
end

-- Get list of installed packages (with timeout to prevent UI blocking)
function M.get_installed_packages(filepath)
	filepath = filepath or get_current_filepath()
	if not M.has_venv(filepath) then
		return {}
	end

	-- UV venv but no UV available - can't list packages
	if M.venv_uses_uv(filepath) and vim.fn.executable("uv") == 0 then
		return {}
	end

	-- Regular pip venv without pip - can't list packages
	if not M.venv_uses_uv(filepath) and not M.get_pip_path(filepath) then
		return {}
	end

	local cmd = build_pip_command("list", nil, filepath, { format = "freeze", quiet = true })
	local success, output, _ = utils.system_with_timeout(cmd, PIP_LIST_TIMEOUT_MS)

	if not success then
		return {}
	end

	local installed = {}
	for line in output:gmatch("[^\r\n]+") do
		local pkg = line:match("^([^=]+)")
		if pkg then
			table.insert(installed, pkg:lower())
		end
	end

	return installed
end

-- Install packages
function M.install_packages(package_list, filepath)
	filepath = filepath or get_current_filepath()
	if not M.has_venv(filepath) then
		if not M.create_venv(filepath) then
			return false
		end
	end

	if #package_list == 0 then
		return true
	end

	-- Get the correct package manager command
	local package_manager = M.get_package_manager(filepath)

	-- Verify the package manager is available
	local is_uv = package_manager:match("^uv")
	if is_uv then
		if vim.fn.executable("uv") == 0 then
			notifications.notify_error("uv not found but required for this venv")
			return false
		end
	else
		-- Check pip exists
		if vim.fn.executable(package_manager) == 0 then
			notifications.notify_error("Package manager not found: " .. package_manager)
			return false
		end
	end

	local packages_str = table.concat(package_list, " ")

	notifications.progress_start(
		"python_packages",
		"Installing Packages",
		string.format("Installing %d packages...", #package_list)
	)

	local project_dir = utils.get_project_paths(filepath)
	local cmd = build_pip_command("install", packages_str, filepath)

	-- Ensure project_dir is valid
	if not project_dir or project_dir == "" then
		notifications.notify_error("Project directory is nil or empty for file: " .. (filepath or "nil"))
		return false
	end

	if vim.fn.isdirectory(project_dir) ~= 1 then
		notifications.notify_error(
			string.format("Project directory does not exist: '%s' (from file: %s)", project_dir, filepath or "nil")
		)
		return false
	end

	-- Log the command being executed
	notifications.notify(string.format("Executing: %s", cmd), vim.log.levels.INFO)
	notifications.notify(string.format("In directory: %s", project_dir), vim.log.levels.INFO)

	-- vim.system requires a table; wrap string commands in shell invocation
	local cmd_table = type(cmd) == "string" and { "sh", "-c", cmd } or cmd

	-- Create async job to install packages using vim.system (Neovim 0.10+)
	local ok, sys_obj = pcall(vim.system, cmd_table, {
		text = true,
		cwd = project_dir,
	}, function(obj)
		vim.schedule(function()
			if obj.code == 0 then
				notifications.progress_finish("python_packages", "Packages installed successfully")
				for _, pkg in ipairs(package_list) do
					state.mark_package_installed("python", pkg)
				end
				cache.invalidate("installed_packages_python")
				cache.invalidate_pattern("imports_")
			else
				notifications.progress_finish("python_packages")

				-- Build output for error buffer
				local stdout = obj.stdout or ""
				local stderr = obj.stderr or ""
				local all_output = {}
				for line in stdout:gmatch("[^\r\n]+") do
					table.insert(all_output, "[STDOUT] " .. line)
				end
				for line in stderr:gmatch("[^\r\n]+") do
					table.insert(all_output, "[STDERR] " .. line)
				end

				-- Create a detailed error buffer
				vim.cmd("new")
				vim.bo.buftype = "nofile"
				vim.bo.bufhidden = "wipe"
				vim.bo.swapfile = false
				vim.bo.filetype = "text"
				vim.api.nvim_buf_set_name(0, "Package Installation Error")

				local error_report = {
					"PACKAGE INSTALLATION FAILED",
					"=" .. string.rep("=", 60),
					"",
					"Command: " .. cmd,
					"Directory: " .. project_dir,
					"Exit code: " .. obj.code,
					"Packages attempted: " .. packages_str,
					"",
					"=" .. string.rep("=", 60),
					"FULL OUTPUT:",
					"=" .. string.rep("=", 60),
					"",
				}

				vim.list_extend(error_report, all_output)

				error_report[#error_report + 1] = ""
				error_report[#error_report + 1] = "=" .. string.rep("=", 60)
				error_report[#error_report + 1] = "ERROR ANALYSIS:"
				error_report[#error_report + 1] = "=" .. string.rep("=", 60)

				for line in stderr:gmatch("[^\r\n]+") do
					if
						line:match("No solution found")
						or line:match("Because")
						or line:match("requires")
						or line:match("depends")
					then
						error_report[#error_report + 1] = "• " .. line
					end
				end

				error_report[#error_report + 1] = ""
				error_report[#error_report + 1] = "=" .. string.rep("=", 60)
				error_report[#error_report + 1] = "TROUBLESHOOTING:"
				error_report[#error_report + 1] = "=" .. string.rep("=", 60)
				error_report[#error_report + 1] = "1. Try installing packages one by one to identify conflicts"
				error_report[#error_report + 1] = "2. Check Python version compatibility"
				error_report[#error_report + 1] =
					"3. For UV: Consider using 'uv pip install --no-deps' for problematic packages"
				error_report[#error_report + 1] = "4. Use :PyworksListPython to see currently installed packages"
				error_report[#error_report + 1] = ""
				error_report[#error_report + 1] = "Press 'q' to close this buffer"

				vim.api.nvim_buf_set_lines(0, 0, -1, false, error_report)
				vim.bo.modifiable = false
				vim.bo.readonly = true
				vim.keymap.set("n", "q", ":close<CR>", { buffer = true, silent = true })

				notifications.notify_error("Package installation failed. See error buffer for details.")
			end
		end)
	end)

	if not ok then
		notifications.notify_error("Failed to start package installation: " .. tostring(sys_obj))
		return false
	end

	return true
end

-- Ensure Python environment is ready
function M.ensure_environment(filepath)
	-- Use provided filepath or fall back to current buffer
	filepath = filepath or get_current_filepath()

	-- Check cache first
	if not state.should_check("python_env", "python", 30) then
		return true
	end

	state.set_last_check("python_env", "python")

	-- Step 1: Check/create venv
	if not M.has_venv(filepath) then
		if not M.create_venv(filepath) then
			return false
		end
	end

	-- Step 2: Install essentials
	if config.auto_install_essentials then
		M.install_essentials(filepath)
	end

	-- Step 3: Notify environment ready
	notifications.notify_environment_ready("python")

	return true
end

-- Handle Python file
function M.handle_file(filepath, is_notebook)
	-- Ensure filepath is absolute
	if filepath and filepath ~= "" and not filepath:match("^/") then
		filepath = vim.fn.fnamemodify(filepath, ":p")
	end

	-- Ensure environment for this specific file's project
	M.ensure_environment(filepath)

	-- Detect missing packages (async to avoid blocking file open)
	vim.defer_fn(function()
		local missing = get_packages().detect_missing_packages(filepath, "python")

		if #missing > 0 then
			notifications.notify_missing_packages(missing, "python")

			-- Store missing packages for leader-pi command
			state.set(state.KEYS.MISSING_PACKAGES .. "python", missing)
		else
			-- Clear any previous missing packages
			state.remove(state.KEYS.MISSING_PACKAGES .. "python")
		end
	end, 100) -- Small delay to avoid blocking file open

	-- If it's a notebook, ensure jupytext
	if is_notebook then
		local jupytext = require("pyworks.notebook.jupytext")
		jupytext.ensure_jupytext()
	end
end

-- Install missing packages command
function M.install_missing_packages()
	local missing = state.get(state.KEYS.MISSING_PACKAGES .. "python") or {}

	if #missing == 0 then
		notifications.notify("No missing packages detected", vim.log.levels.INFO)
		return
	end

	-- Show which packages we're trying to install
	notifications.notify(
		string.format("Detected %d missing packages: %s", #missing, table.concat(missing, ", ")),
		vim.log.levels.INFO
	)

	-- Get current buffer's filepath
	local filepath = get_current_filepath()
	if not filepath then
		notifications.notify_error("Could not determine file path for package installation")
		return
	end

	-- Check if the file actually exists
	if vim.fn.filereadable(filepath) ~= 1 then
		notifications.notify_error(string.format("File not found: %s", filepath))
		return
	end

	M.install_packages(missing, filepath)
end

-- Install specific Python packages (user command)
function M.install_python_packages(packages_str)
	-- Get current file context
	local filepath = get_current_filepath()
	if filepath == "" then
		filepath = nil
	end

	-- Parse packages string (space or comma separated)
	local pkg_list = {}
	for pkg in packages_str:gmatch("[^,%s]+") do
		table.insert(pkg_list, pkg)
	end

	-- Apply package name mappings (e.g., sklearn -> scikit-learn)
	local applied_mappings
	pkg_list, applied_mappings = get_packages().map_packages(pkg_list, "python")
	for original, mapped in pairs(applied_mappings) do
		notifications.notify(string.format("📦 Mapping '%s' → '%s'", original, mapped), vim.log.levels.INFO)
	end

	-- Validate packages
	pkg_list = error_handler.validate_packages(pkg_list, "Python")
	if not pkg_list then
		return
	end

	-- Ensure environment exists
	if not M.has_venv(filepath) then
		notifications.notify("Creating Python virtual environment first...", vim.log.levels.INFO)
		local ok = error_handler.protected_call(M.create_venv, "Failed to create virtual environment", filepath)
		if not ok then
			return
		end
	end

	notifications.notify(
		string.format("Installing Python packages: %s", table.concat(pkg_list, ", ")),
		vim.log.levels.INFO
	)
	M.install_packages(pkg_list, filepath)
end

-- Uninstall Python packages (user command)
function M.uninstall_python_packages(packages_str)
	-- Get current file context
	local filepath = get_current_filepath()
	if filepath == "" then
		filepath = nil
	end

	-- Check venv exists
	if not M.has_venv(filepath) then
		notifications.notify_error("No Python virtual environment found")
		return
	end

	-- Parse packages string
	local pkg_list = {}
	for pkg in packages_str:gmatch("[^,%s]+") do
		table.insert(pkg_list, pkg)
	end

	-- Validate packages
	pkg_list = error_handler.validate_packages(pkg_list, "Python")
	if not pkg_list then
		return
	end

	local project_dir = utils.get_project_paths(filepath)
	local packages_str_clean = table.concat(pkg_list, " ")
	local cmd = build_pip_command("uninstall", packages_str_clean, filepath, { yes = true })

	notifications.notify(string.format("Uninstalling Python packages: %s", packages_str_clean), vim.log.levels.INFO)

	-- vim.system requires a table; wrap string commands in shell invocation
	local cmd_table = type(cmd) == "string" and { "sh", "-c", cmd } or cmd

	-- Execute uninstall using vim.system (Neovim 0.10+)
	local ok, _ = pcall(vim.system, cmd_table, {
		text = true,
		cwd = project_dir,
	}, function(obj)
		vim.schedule(function()
			if obj.code == 0 then
				notifications.notify("Packages uninstalled successfully", vim.log.levels.INFO)
				cache.invalidate("installed_packages_python")
			else
				notifications.notify_error("Failed to uninstall some packages")
			end
		end)
	end)

	if not ok then
		notifications.notify_error("Failed to start uninstall command")
	end
end

-- List installed Python packages (with timeout to prevent UI blocking)
function M.list_python_packages()
	local filepath = get_current_filepath()
	if filepath == "" then
		filepath = nil
	end

	if not M.has_venv(filepath) then
		notifications.notify_error("No Python virtual environment found")
		return
	end

	-- UV venv but no UV available
	if M.venv_uses_uv(filepath) and vim.fn.executable("uv") == 0 then
		notifications.notify_error("uv not found but required for this venv")
		return
	end

	-- Regular pip venv without pip
	if not M.venv_uses_uv(filepath) and not M.get_pip_path(filepath) then
		notifications.notify_error("pip not found in virtual environment")
		return
	end

	local cmd = build_pip_command("list", nil, filepath)
	local success, output, _ = utils.system_with_timeout(cmd, PIP_LIST_TIMEOUT_MS)

	if success then
		local ui = require("pyworks.ui")

		-- Parse output into lines
		local lines = vim.split(output, "\n")
		local content = { "" }

		for _, line in ipairs(lines) do
			if line ~= "" then
				table.insert(content, "  " .. line)
			end
		end
		table.insert(content, "")
		table.insert(content, "  Press q or <Esc> to close")
		table.insert(content, "")

		ui.create_floating_window(" Installed Packages ", content, { height = 30 })
	else
		notifications.notify_error("Failed to list packages")
	end
end

-- Check Python version compatibility (with timeout)
function M.check_compatibility(package_name, filepath)
	filepath = filepath or get_current_filepath()
	local python_path = M.get_python_path(filepath) or "python3"

	-- Get Python version (with timeout)
	local cmd = string.format("%s --version 2>&1", python_path)
	local success, version_output, _ = utils.system_with_timeout(cmd, IMPORT_CHECK_TIMEOUT_MS)
	if not success then
		return nil
	end
	local major, minor = version_output:match("Python (%d+)%.(%d+)")

	if not major then
		return nil
	end

	local py_version = tonumber(major) + tonumber(minor) / 10

	-- Check known compatibility issues
	local compatibility_issues = {
		tensorflow = {
			max_version = 3.11,
			message = "TensorFlow may not be compatible with Python 3.12+",
		},
		numpy = {
			min_version = 3.8,
			message = "NumPy requires Python 3.8+",
		},
	}

	local issue = compatibility_issues[package_name:lower()]
	if issue then
		if issue.max_version and py_version > issue.max_version then
			return issue.message
		end
		if issue.min_version and py_version < issue.min_version then
			return issue.message
		end
	end

	return nil
end

return M
