-- Python language support for pyworks.nvim
-- Handles Python files and notebooks with Python kernels

local M = {}

local cache = require("pyworks.core.cache")
local notifications = require("pyworks.core.notifications")
local packages = require("pyworks.core.packages")
local state = require("pyworks.core.state")

-- Configuration
local config = {
	use_uv = false,
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
function M.has_venv()
	return vim.fn.isdirectory(config.preferred_venv_name) == 1
end

-- Get Python path
function M.get_python_path()
	if M.has_venv() then
		local cwd = vim.fn.getcwd()
		return cwd .. "/" .. config.preferred_venv_name .. "/bin/python"
	end
	return nil
end

-- Get pip path
function M.get_pip_path()
	if M.has_venv() then
		local cwd = vim.fn.getcwd()
		return cwd .. "/" .. config.preferred_venv_name .. "/bin/pip"
	end
	return nil
end

-- Check if venv uses uv
function M.venv_uses_uv()
	if not M.has_venv() then
		return false
	end

	-- Check for uv.lock or if venv was created by uv
	-- uv venvs typically have a pyvenv.cfg with "uv" mentioned
	local pyvenv_cfg = config.preferred_venv_name .. "/pyvenv.cfg"
	if vim.fn.filereadable(pyvenv_cfg) == 1 then
		local content = vim.fn.readfile(pyvenv_cfg)
		for _, line in ipairs(content) do
			if line:match("uv") then
				return true
			end
		end
	end

	-- Also check if uv.lock exists in the project
	return vim.fn.filereadable("uv.lock") == 1
end

-- Determine which package manager to use
function M.get_package_manager()
	if M.has_venv() then
		local cwd = vim.fn.getcwd()
		-- If venv was created with uv, we need to use uv pip
		if M.venv_uses_uv() then
			-- uv pip needs to be called from outside venv
			if vim.fn.executable("uv") == 1 then
				return "uv pip"
			else
				-- Fallback to pip if uv not available
				return cwd .. "/" .. config.preferred_venv_name .. "/bin/pip"
			end
		else
			-- Regular pip venv
			return cwd .. "/" .. config.preferred_venv_name .. "/bin/pip"
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
function M.create_venv()
	if M.has_venv() then
		return true
	end

	notifications.progress_start("python_venv", "Python Setup", "Creating virtual environment...")

	local cmd
	if config.use_uv and vim.fn.executable("uv") == 1 then
		-- Use uv for speed
		cmd = string.format("uv venv %s", config.preferred_venv_name)
	else
		-- Use standard venv
		local python = vim.fn.executable("python3") == 1 and "python3" or "python"
		cmd = string.format("%s -m venv %s", python, config.preferred_venv_name)
	end

	local result = vim.fn.system(cmd)
	local success = vim.v.shell_error == 0

	if success then
		notifications.progress_finish("python_venv", "Virtual environment created")
		cache.invalidate("venv_check")
		state.set_env_status("python", "venv_created")
	else
		notifications.progress_finish("python_venv")
		notifications.notify_error("Failed to create virtual environment")
	end

	return success
end

-- Install essential packages
function M.install_essentials()
	if not M.has_venv() then
		if not M.create_venv() then
			return false
		end
	end

	-- Wait a bit for venv to be ready
	vim.wait(500)

	-- Check if essentials are already installed
	local missing_essentials = {}
	for _, pkg in ipairs(config.essentials) do
		if not M.is_package_installed(pkg) then
			table.insert(missing_essentials, pkg)
		end
	end

	if #missing_essentials == 0 then
		return true
	end

	notifications.progress_start(
		"python_essentials",
		"Python Setup",
		string.format(
			"Installing %d essential packages: %s",
			#missing_essentials,
			table.concat(missing_essentials, ", ")
		)
	)

	-- Get the correct package manager command
	local package_manager = M.get_package_manager()

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
		vim.fn.system(package_manager .. " install --upgrade pip 2>/dev/null")
	end

	local packages_str = table.concat(missing_essentials, " ")
	local cmd = string.format("%s install %s", package_manager, packages_str)

	-- Log the command for debugging
	vim.notify("[Pyworks Debug] Running: " .. cmd, vim.log.levels.DEBUG)

	local error_output = {}
	vim.fn.jobstart(cmd, {
		cwd = vim.fn.getcwd(),
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					vim.schedule(function()
						notifications.progress_update("python_essentials", line, 50)
					end)
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					-- uv outputs progress to stderr, not an error
					if line:match("Installed %d+ package") then
						vim.schedule(function()
							vim.notify("[Pyworks] " .. line, vim.log.levels.INFO)
						end)
					elseif not line:match("WARNING") and not line:match("Resolved") then
						table.insert(error_output, line)
						vim.schedule(function()
							vim.notify("[Pyworks] " .. line, vim.log.levels.DEBUG)
						end)
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
function M.is_package_installed(package_name)
	local python_path = M.get_python_path()
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
function M.get_installed_packages()
	if not M.has_venv() then
		return {}
	end

	local pip_path = M.get_pip_path()
	if not pip_path then
		return {}
	end

	local cmd = string.format("%s list --format=freeze 2>/dev/null", pip_path)
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
function M.install_packages(package_list)
	if not M.has_venv() then
		if not M.create_venv() then
			return false
		end
	end

	if #package_list == 0 then
		return true
	end

	-- Get the correct package manager command
	local package_manager = M.get_package_manager()

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

	local cmd = string.format("%s install %s", package_manager, packages_str)

	-- Create a job to install packages
	local job_id = vim.fn.jobstart(cmd, {
		cwd = vim.fn.getcwd(),
		on_stdout = function(_, data)
			vim.schedule(function()
				-- Update progress with package names as they install
				for _, line in ipairs(data) do
					if line:match("Successfully installed") or line:match("Collecting") then
						notifications.progress_update("python_packages", line, 90)
					end
				end
			end)
		end,
		on_stderr = function(_, data)
			vim.schedule(function()
				for _, line in ipairs(data) do
					if line ~= "" then
						-- uv outputs progress to stderr, not an error
						if line:match("Installed %d+ package") or line:match("Resolved %d+ package") then
							-- Don't spam with every package when not in debug mode
							if notifications.get_config().debug_mode then
								vim.notify("[Pyworks] " .. line, vim.log.levels.INFO)
							end
						elseif not line:match("WARNING") and notifications.get_config().debug_mode then
							vim.notify("[Pyworks] " .. line, vim.log.levels.DEBUG)
						end
					end
				end
			end)
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
					notifications.notify_error("Failed to install some packages. Check :messages for details.")
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
function M.ensure_environment()
	-- Check cache first
	if not state.should_check("python_env", "python", 30) then
		return true
	end

	state.set_last_check("python_env", "python")

	-- Step 1: Check/create venv
	if not M.has_venv() then
		if not M.create_venv() then
			return false
		end
	end

	-- Step 2: Install essentials
	if config.auto_install_essentials then
		M.install_essentials()
	end

	-- Step 3: Notify environment ready
	notifications.notify_environment_ready("python")

	return true
end

-- Handle Python file
function M.handle_file(filepath, is_notebook)
	-- Ensure environment
	M.ensure_environment()

	-- Detect missing packages
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
	end, 500) -- Small delay to let environment setup complete

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

	M.install_packages(missing)
end

-- Check Python version compatibility
function M.check_compatibility(package_name)
	local python_path = M.get_python_path() or "python3"

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

