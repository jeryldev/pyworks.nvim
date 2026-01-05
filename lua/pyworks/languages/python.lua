-- Python language support for pyworks.nvim
-- Handles Python files and notebooks with Python kernels

local M = {}

local cache = require("pyworks.core.cache")
local error_handler = require("pyworks.core.error_handler")
local notifications = require("pyworks.core.notifications")
local packages = require("pyworks.core.packages")
local state = require("pyworks.core.state")
local utils = require("pyworks.utils")

-- Track current file being processed
local current_filepath = nil

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

-- Create virtual environment
function M.create_venv(filepath)
	filepath = filepath or current_filepath
	if M.has_venv(filepath) then
		return true
	end

	notifications.progress_start("python_venv", "Python Setup", "Creating virtual environment...")

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

	-- Execute command (no need to cd, using full paths)
	local result = vim.fn.system(cmd)
	local success = vim.v.shell_error == 0

	if success then
		notifications.progress_finish("python_venv", "Virtual environment created" .. (use_uv and " with uv" or ""))
		cache.invalidate("venv_check")
		state.set_env_status("python", "venv_created")
	else
		notifications.progress_finish("python_venv")
		local error_msg =
			string.format("Failed to create venv. Command: %s, Error: %s", table.concat(cmd, " "), result or "unknown")
		notifications.notify_error(error_msg)
	end

	return success
end

-- Install essential packages
function M.install_essentials(filepath)
	filepath = filepath or current_filepath
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

	notifications.progress_start(
		"python_essentials",
		"Python Setup",
		string.format("Installing %d essential packages...", #missing_essentials)
	)

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

	-- Get project directory for this file (first return value)
	local project_dir, venv_path = utils.get_project_paths(filepath)

	-- Upgrade pip if using pip (not needed for uv)
	if not is_uv then
		vim.fn.system(package_manager .. " install --upgrade pip 2>/dev/null")
	end

	local packages_str = table.concat(missing_essentials, " ")

	-- Build the install command with proper syntax for UV
	local cmd
	if is_uv then
		-- For UV, use --python flag to specify the venv's Python
		local python_path = venv_path .. "/bin/python"
		cmd = string.format("uv pip install --python %s %s", vim.fn.shellescape(python_path), packages_str)
	else
		-- Regular pip command
		cmd = string.format("%s install %s", package_manager, packages_str)
	end

	-- Log the command for debugging
	vim.notify("[Pyworks Debug] Running: " .. cmd, vim.log.levels.DEBUG)

	-- Ensure project_dir is valid
	if not project_dir or vim.fn.isdirectory(project_dir) ~= 1 then
		notifications.notify_error("Invalid project directory for essentials: " .. (project_dir or "nil"))
		return false
	end

	local error_output = {}
	vim.fn.jobstart(cmd, {
		cwd = project_dir,
		on_stdout = function(_, data)
			-- Silent - don't show every package being installed
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					-- Only collect actual errors (not progress output)
					if
						not line:match("WARNING")
						and not line:match("Resolved")
						and not line:match("Installed")
						and not line:match("Collecting")
						and not line:match("Installing")
					then
						table.insert(error_output, line)
					end
				end
			end
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				if code == 0 then
					notifications.progress_finish("python_essentials", "Essential packages installed")
					-- Mark packages as installed
					for _, pkg in ipairs(missing_essentials) do
						state.mark_package_installed("python", pkg)
					end
					cache.invalidate("installed_packages_python")
				else
					notifications.progress_finish("python_essentials")
					local error_msg = "Failed to install essential packages."
					if #error_output > 0 then
						error_msg = error_msg .. "\nError: " .. table.concat(error_output, "\n")
					end
					notifications.notify_error(error_msg)
					vim.notify("[Pyworks] Installation command was: " .. cmd, vim.log.levels.ERROR)
				end
			end)
		end,
	})

	return true
end

-- Check if a package is installed
function M.is_package_installed(package_name, filepath)
	filepath = filepath or current_filepath
	local python_path = M.get_python_path(filepath)
	if not python_path then
		return false
	end

	-- Try to import the package
	local import_name = package_name
	-- Handle special cases
	if package_name == "scikit-learn" then
		import_name = "sklearn"
	elseif package_name == "opencv-python" then
		import_name = "cv2"
	elseif package_name == "Pillow" then
		import_name = "PIL"
	elseif package_name == "beautifulsoup4" then
		import_name = "bs4"
	elseif package_name == "ipykernel" then
		import_name = "ipykernel"
	elseif package_name == "jupyter_client" then
		import_name = "jupyter_client"
	elseif package_name == "jupytext" then
		import_name = "jupytext"
	elseif package_name == "pynvim" then
		import_name = "pynvim"
	end

	-- Python path already has full path from get_python_path()
	local cmd = string.format("%s -c 'import %s' 2>/dev/null", python_path, import_name)
	vim.fn.system(cmd)
	return vim.v.shell_error == 0
end

-- Get list of installed packages
function M.get_installed_packages(filepath)
	filepath = filepath or current_filepath
	if not M.has_venv(filepath) then
		return {}
	end

	local cmd
	local project_dir, venv_path = utils.get_project_paths(filepath)
	local python_path = venv_path .. "/bin/python"

	-- Check if this is a UV venv
	if M.venv_uses_uv(filepath) then
		-- For UV venvs, use 'uv pip list' with the specific Python interpreter
		if vim.fn.executable("uv") == 1 then
			-- Use --python to specify the venv's Python interpreter
			cmd = string.format("uv pip list --python %s --format=freeze 2>/dev/null", vim.fn.shellescape(python_path))
		else
			-- UV venv but no UV available - can't list packages
			return {}
		end
	else
		-- Regular pip venv
		local pip_path = M.get_pip_path(filepath)
		if not pip_path then
			return {}
		end
		cmd = string.format("%s list --format=freeze 2>/dev/null", pip_path)
	end

	local output = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
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
	filepath = filepath or current_filepath
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

	-- Get project directory for this file (first return value)
	local project_dir, venv_path = utils.get_project_paths(filepath)

	-- Build the install command with proper syntax for UV
	local cmd
	if is_uv then
		-- For UV, use --python flag to specify the venv's Python
		local python_path = venv_path .. "/bin/python"
		cmd = string.format("uv pip install --python %s %s", vim.fn.shellescape(python_path), packages_str)
	else
		-- Regular pip command
		cmd = string.format("%s install %s", package_manager, packages_str)
	end

	-- Debug: Show what we got
	-- notifications.notify(string.format("Debug: filepath=%s, project_dir=%s", filepath or "nil", project_dir or "nil"), vim.log.levels.WARN)

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

	-- Track output for better error reporting
	local error_lines = {}
	local success_output = {}
	local all_output = {} -- Keep ALL output for debugging

	-- Log the command being executed
	notifications.notify(string.format("Executing: %s", cmd), vim.log.levels.INFO)
	notifications.notify(string.format("In directory: %s", project_dir), vim.log.levels.INFO)

	-- Create a job to install packages
	local job_id = vim.fn.jobstart(cmd, {
		cwd = project_dir,
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(success_output, line)
					table.insert(all_output, "[STDOUT] " .. line)
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(all_output, "[STDERR] " .. line)
					-- Capture ALL stderr for debugging, not just errors
					table.insert(error_lines, line)
				end
			end
		end,
		on_exit = function(job_id_exit, code)
			vim.schedule(function()
				if code == 0 then
					notifications.progress_finish("python_packages", "Packages installed successfully")
					-- Mark packages as installed
					for _, pkg in ipairs(package_list) do
						state.mark_package_installed("python", pkg)
					end
					-- Invalidate cache
					cache.invalidate("installed_packages_python")
					cache.invalidate_pattern("imports_")
				else
					notifications.progress_finish("python_packages")

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
						"Exit code: " .. code,
						"Packages attempted: " .. packages_str,
						"",
						"=" .. string.rep("=", 60),
						"FULL OUTPUT:",
						"=" .. string.rep("=", 60),
						"",
					}

					-- Add all output
					vim.list_extend(error_report, all_output)

					-- Add specific error analysis
					error_report[#error_report + 1] = ""
					error_report[#error_report + 1] = "=" .. string.rep("=", 60)
					error_report[#error_report + 1] = "ERROR ANALYSIS:"
					error_report[#error_report + 1] = "=" .. string.rep("=", 60)

					-- Look for specific UV resolution errors
					for _, line in ipairs(error_lines) do
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

					-- Set buffer content
					vim.api.nvim_buf_set_lines(0, 0, -1, false, error_report)

					-- Make read-only and add keymap
					vim.bo.modifiable = false
					vim.bo.readonly = true
					vim.keymap.set("n", "q", ":close<CR>", { buffer = true, silent = true })

					-- Also show a short notification
					notifications.notify_error("Package installation failed. See error buffer for details.")
				end

				-- Remove job from active jobs (use the job_id from on_exit parameter)
				if job_id_exit and job_id_exit > 0 then
					state.remove_job(job_id_exit)
				end
			end)
		end,
	})

	-- Track active job only if job started successfully
	if job_id and job_id > 0 then
		state.add_job(job_id, {
			type = "package_install",
			language = "python",
			packages = package_list,
			started = os.time(),
		})
	else
		notifications.notify_error("Failed to start package installation job")
		return false
	end

	return true
end

-- Ensure Python environment is ready
function M.ensure_environment(filepath)
	-- Use provided filepath or fall back to current_filepath
	filepath = filepath or current_filepath

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
	-- Store current filepath for other functions to use
	-- Make sure it's absolute
	if filepath and filepath ~= "" then
		if not filepath:match("^/") then
			filepath = vim.fn.fnamemodify(filepath, ":p")
		end
		current_filepath = filepath
	end

	-- Ensure environment for this specific file's project
	M.ensure_environment(filepath)

	-- Detect missing packages (async to avoid blocking file open)
	vim.defer_fn(function()
		local missing = packages.detect_missing_packages(filepath, "python")

		if #missing > 0 then
			notifications.notify_missing_packages(missing, "python")

			-- Store missing packages for leader-pi command
			state.set("missing_packages_python", missing)
		else
			-- Clear any previous missing packages
			state.remove("missing_packages_python")
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
	local missing = state.get("missing_packages_python") or {}

	if #missing == 0 then
		notifications.notify("No missing packages detected", vim.log.levels.INFO)
		return
	end

	-- Show which packages we're trying to install
	notifications.notify(
		string.format("Detected %d missing packages: %s", #missing, table.concat(missing, ", ")),
		vim.log.levels.INFO
	)

	-- Get current buffer's filepath if not already set
	local filepath = current_filepath
	if not filepath or filepath == "" then
		-- Primary method: Use vim.fn.expand which handles all cases
		filepath = vim.fn.expand("%:p")

		-- Fallback: If expand didn't work, use nvim_buf_get_name
		if filepath == "" then
			local bufname = vim.api.nvim_buf_get_name(0)
			if bufname ~= "" then
				-- Make it absolute if it's relative
				if not bufname:match("^/") and not bufname:match("^~") then
					-- It's a relative path, make it absolute
					filepath = vim.fn.fnamemodify(bufname, ":p")
				else
					filepath = bufname
				end
			end
		end
	end

	-- Final validation and error reporting
	if not filepath or filepath == "" then
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
	local filepath = current_filepath or vim.fn.expand("%:p")
	if filepath == "" then
		filepath = nil
	end

	-- Parse packages string (space or comma separated)
	local pkg_list = {}
	for pkg in packages_str:gmatch("[^,%s]+") do
		table.insert(pkg_list, pkg)
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
	local filepath = current_filepath or vim.fn.expand("%:p")
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

	-- Get package manager
	local package_manager = M.get_package_manager(filepath)
	local project_dir, venv_path = utils.get_project_paths(filepath)

	-- Build uninstall command
	local packages_str_clean = table.concat(pkg_list, " ")
	local cmd
	local is_uv = package_manager:match("^uv")
	if is_uv then
		-- For UV, use --python flag to specify the venv's Python
		local python_path = venv_path .. "/bin/python"
		cmd = string.format("uv pip uninstall --python %s %s", vim.fn.shellescape(python_path), packages_str_clean)
	else
		-- Regular pip command
		cmd = string.format("%s uninstall -y %s", package_manager, packages_str_clean)
	end

	notifications.notify(string.format("Uninstalling Python packages: %s", packages_str_clean), vim.log.levels.INFO)

	-- Execute uninstall
	local job_id = vim.fn.jobstart(cmd, {
		cwd = project_dir,
		on_exit = function(_, code)
			vim.schedule(function()
				if code == 0 then
					notifications.notify("Packages uninstalled successfully", vim.log.levels.INFO)
					-- Invalidate cache
					cache.invalidate("installed_packages_python")
				else
					notifications.notify_error("Failed to uninstall some packages")
				end
			end)
		end,
	})

	if not job_id or job_id <= 0 then
		notifications.notify_error("Failed to start uninstall command")
	end
end

-- List installed Python packages
function M.list_python_packages()
	local filepath = current_filepath or vim.fn.expand("%:p")
	if filepath == "" then
		filepath = nil
	end

	if not M.has_venv(filepath) then
		notifications.notify_error("No Python virtual environment found")
		return
	end

	-- Determine command based on package manager (uv or pip)
	local cmd
	if M.venv_uses_uv(filepath) and vim.fn.executable("uv") == 1 then
		local project_dir, _ = utils.get_project_paths(filepath)
		cmd = string.format("cd %s && uv pip list", vim.fn.shellescape(project_dir))
	else
		local pip_path = M.get_pip_path(filepath)
		if not pip_path then
			notifications.notify_error("pip not found in virtual environment")
			return
		end
		cmd = string.format("%s list", pip_path)
	end

	local output = vim.fn.system(cmd)

	if vim.v.shell_error == 0 then
		-- Create a new buffer to show the output
		vim.cmd("new")
		vim.bo.buftype = "nofile"
		vim.bo.bufhidden = "wipe"
		vim.bo.swapfile = false
		vim.bo.filetype = "text"

		-- Set buffer name
		vim.api.nvim_buf_set_name(0, "Python Packages")

		-- Add content
		local lines = vim.split(output, "\n")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

		-- Make it read-only
		vim.bo.modifiable = false
		vim.bo.readonly = true

		-- Add keymap to close with q
		vim.keymap.set("n", "q", ":close<CR>", { buffer = true, silent = true })
	else
		notifications.notify_error("Failed to list packages")
	end
end

-- Check Python version compatibility
function M.check_compatibility(package_name, filepath)
	filepath = filepath or current_filepath
	local python_path = M.get_python_path(filepath) or "python3"

	-- Get Python version
	local cmd = string.format("%s --version 2>&1", python_path)
	local version_output = vim.fn.system(cmd)
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
