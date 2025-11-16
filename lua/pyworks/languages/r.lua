-- R language support for pyworks.nvim
-- Handles R files and notebooks with R kernels

local M = {}

local cache = require("pyworks.core.cache")
local error_handler = require("pyworks.core.error_handler")
local notifications = require("pyworks.core.notifications")
local packages = require("pyworks.core.packages")
local state = require("pyworks.core.state")

-- Check if R is installed
function M.has_r()
	return vim.fn.executable("R") == 1 or vim.fn.executable("Rscript") == 1
end

-- Get R path
function M.get_r_path()
	if vim.fn.executable("R") == 1 then
		return "R"
	elseif vim.fn.executable("Rscript") == 1 then
		return "Rscript"
	end
	return nil
end

-- Check if IRkernel is installed
function M.has_irkernel()
	-- Check cache first
	local cached = cache.get("irkernel_check")
	if cached ~= nil then
		return cached
	end

	local r_path = M.get_r_path()
	if not r_path then
		cache.set("irkernel_check", false)
		return false
	end

	-- Check for IRkernel package
	local cmd
	if r_path == "R" then
		cmd = string.format(
			"%s --slave -e \"if('IRkernel' %%in%% installed.packages()[,1]) quit(status=0) else quit(status=1)\" 2>/dev/null",
			r_path
		)
	else
		cmd = string.format(
			"%s -e \"if('IRkernel' %%in%% installed.packages()[,1]) quit(status=0) else quit(status=1)\" 2>/dev/null",
			r_path
		)
	end

	vim.fn.system(cmd)
	local has_irkernel = vim.v.shell_error == 0

	-- Cache the result
	cache.set("irkernel_check", has_irkernel)

	return has_irkernel
end

-- Install IRkernel
function M.install_irkernel()
	local r_path = M.get_r_path()
	if not r_path then
		notifications.notify_error("R not found. Please install R first.")
		return false
	end

	notifications.progress_start("irkernel_install", "R Setup", "Installing IRkernel...")

	-- Install IRkernel and register it
	local install_cmd
	if r_path == "R" then
		install_cmd = string.format(
			"%s --slave -e \"install.packages('IRkernel', repos='https://cloud.r-project.org/'); IRkernel::installspec(user=TRUE)\"",
			r_path
		)
	else
		install_cmd = string.format(
			"%s -e \"install.packages('IRkernel', repos='https://cloud.r-project.org/'); IRkernel::installspec(user=TRUE)\"",
			r_path
		)
	end

	vim.fn.jobstart(install_cmd, {
		on_exit = function(_, code)
			if code == 0 then
				cache.invalidate("irkernel_check")
				notifications.progress_finish("irkernel_install", "IRkernel installed successfully")
				state.set("persistent_irkernel_installed", true)
			else
				notifications.progress_finish("irkernel_install")
				notifications.notify_error("Failed to install IRkernel")
			end
		end,
	})

	return true
end

-- Ensure IRkernel is available
function M.ensure_irkernel()
	if M.has_irkernel() then
		return true -- Already installed, nothing to do
	end

	-- Check if we've already prompted before
	local prompted = state.get("irkernel_prompted")
	if prompted then
		return false -- Already prompted, don't ask again
	end

	-- First time - ask user once
	state.set("irkernel_prompted", true)
	vim.ui.select({ "Yes", "No" }, {
		prompt = "IRkernel is required for R notebooks. Install it?",
	}, function(choice)
		if choice == "Yes" then
			M.install_irkernel()
		end
	end)
	return false
end

-- Check if renv.lock exists (R's virtual environment)
function M.has_renv()
	return vim.fn.filereadable("renv.lock") == 1
end

-- Activate renv if present
function M.activate_renv()
	if not M.has_renv() then
		return true
	end

	local r_path = M.get_r_path()
	if not r_path then
		return false
	end

	-- Activate renv
	local cmd
	if r_path == "R" then
		cmd = string.format('%s --slave -e "renv::restore()" 2>/dev/null', r_path)
	else
		cmd = string.format('%s -e "renv::restore()" 2>/dev/null', r_path)
	end

	vim.fn.system(cmd)
	return vim.v.shell_error == 0
end

-- Get list of installed packages
function M.get_installed_packages(filepath)
	-- R packages can be in different libraries based on renv
	-- For now, we'll check the default library (filepath param kept for consistency)
	local r_path = M.get_r_path()
	if not r_path then
		return {}
	end

	-- Get installed packages
	local cmd
	if r_path == "R" then
		cmd = string.format("%s --slave -e \"cat(installed.packages()[,1], sep='\\n')\" 2>/dev/null", r_path)
	else
		cmd = string.format("%s -e \"cat(installed.packages()[,1], sep='\\n')\" 2>/dev/null", r_path)
	end

	local output = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		return {}
	end

	local installed = {}
	for line in output:gmatch("[^\r\n]+") do
		if line ~= "" then
			table.insert(installed, line:lower())
		end
	end

	return installed
end

-- Check if a package is installed
function M.is_package_installed(package_name)
	local r_path = M.get_r_path()
	if not r_path then
		return false
	end

	local cmd
	if r_path == "R" then
		cmd = string.format(
			"%s --slave -e \"if('%s' %%in%% installed.packages()[,1]) quit(status=0) else quit(status=1)\" 2>/dev/null",
			r_path,
			package_name
		)
	else
		cmd = string.format(
			"%s -e \"if('%s' %%in%% installed.packages()[,1]) quit(status=0) else quit(status=1)\" 2>/dev/null",
			r_path,
			package_name
		)
	end

	vim.fn.system(cmd)
	return vim.v.shell_error == 0
end

-- Install packages
function M.install_packages(package_list)
	local r_path = M.get_r_path()
	if not r_path then
		notifications.notify_error("R not found. Please install R first.")
		return false
	end

	if #package_list == 0 then
		return true
	end

	notifications.progress_start(
		"r_packages",
		"Installing Packages",
		string.format("Installing %d R packages...", #package_list)
	)

	-- Build install.packages command
	local packages_str = table.concat(
		vim.tbl_map(function(pkg)
			return string.format("'%s'", pkg)
		end, package_list),
		", "
	)

	local cmd
	if r_path == "R" then
		cmd = string.format(
			"%s --slave -e \"install.packages(c(%s), repos='https://cloud.r-project.org/')\"",
			r_path,
			packages_str
		)
	else
		cmd = string.format(
			"%s -e \"install.packages(c(%s), repos='https://cloud.r-project.org/')\"",
			r_path,
			packages_str
		)
	end

	-- Create a job to install packages
	local job_id = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data)
			-- Update progress as packages install
			for _, line in ipairs(data) do
				if line:match("downloaded") or line:match("installed") then
					notifications.progress_update("r_packages", line, 75)
				end
			end
		end,
		on_exit = function(_, code)
			if code == 0 then
				notifications.progress_finish("r_packages", "R packages installed successfully")
				-- Mark packages as installed
				for _, pkg in ipairs(package_list) do
					state.mark_package_installed("r", pkg)
				end
				-- Invalidate cache
				cache.invalidate("installed_packages_r")
			else
				notifications.progress_finish("r_packages")
				notifications.notify_error("Failed to install some R packages")
			end

			-- Remove job from active jobs
			state.remove_job(job_id)
		end,
	})

	-- Track active job
	state.add_job(job_id, {
		type = "package_install",
		language = "r",
		packages = package_list,
		started = os.time(),
	})

	return true
end

-- Ensure R environment is ready
function M.ensure_environment()
	-- Check cache first
	if not state.should_check("r_env", "r", 30) then
		return true
	end

	state.set_last_check("r_env", "r")

	-- Step 1: Check R installation
	if not M.has_r() then
		notifications.notify(
			"R not found. Please install R from https://www.r-project.org",
			vim.log.levels.WARN,
			{ action_required = true }
		)
		return false
	end

	-- Step 2: Activate renv if exists
	if M.has_renv() then
		M.activate_renv()
	end

	-- Step 3: Notify environment ready
	notifications.notify_environment_ready("r")

	return true
end

-- Handle R file
function M.handle_file(filepath, is_notebook)
	-- Ensure environment
	M.ensure_environment()

	-- If it's a notebook, ensure IRkernel
	if is_notebook then
		M.ensure_irkernel()
	end

	-- Detect missing packages
	vim.defer_fn(function()
		local missing = packages.detect_missing_packages(filepath, "r")

		if #missing > 0 then
			notifications.notify_missing_packages(missing, "r")

			-- Store missing packages for leader-pi command
			state.set("missing_packages_r", missing)
		else
			-- Clear any previous missing packages
			state.remove("missing_packages_r")
		end
	end, 500) -- Small delay to let environment setup complete
end

-- Install missing packages command
function M.install_missing_packages()
	local missing = state.get("missing_packages_r") or {}

	if #missing == 0 then
		notifications.notify("No missing R packages detected", vim.log.levels.INFO)
		return
	end

	M.install_packages(missing)
end

-- Setup R REPL integration
function M.setup_repl()
	-- This could integrate with iron.nvim or similar REPL plugins
	-- For now, just ensure R is available
	if not M.has_r() then
		notifications.notify_error("R not found. Cannot start REPL.")
		return false
	end

	-- The actual REPL integration would be handled by iron.nvim
	return true
end

-- Install tidyverse (common R package collection)
function M.install_tidyverse()
	notifications.notify("Installing tidyverse... This may take several minutes.", vim.log.levels.INFO)
	M.install_packages({ "tidyverse" })
end

return M
