-- Essential package management for notebooks
-- Automatically installs required packages for Jupyter functionality
local M = {}
local utils = require("pyworks.utils")
local config = require("pyworks.config")

-- Essential packages for notebook functionality
M.essential_packages = {
	-- Core requirements
	"pynvim",        -- Required for Neovim integration
	"ipykernel",     -- Required for Jupyter kernel
	"jupyter_client", -- Required for kernel communication
	"jupytext",      -- Required for notebook conversion
	-- Additional useful packages
	"ipython",       -- Better REPL experience
	"notebook",      -- Jupyter notebook server
}

-- Check if a package is installed in the given Python environment
function M.is_package_installed(python_path, package)
	local check_cmd = python_path .. " -c 'import " .. package .. "' 2>/dev/null"
	vim.fn.system(check_cmd)
	return vim.v.shell_error == 0
end

-- Get the Python executable for the current project
function M.get_project_python()
	local python_paths = {
		vim.fn.getcwd() .. "/.venv/bin/python3",
		vim.fn.getcwd() .. "/.venv/bin/python",
		vim.fn.getcwd() .. "/venv/bin/python3",
		vim.fn.getcwd() .. "/venv/bin/python",
	}
	
	for _, path in ipairs(python_paths) do
		if vim.fn.executable(path) == 1 then
			return path
		end
	end
	
	return nil
end

-- Install packages synchronously (blocking) - for critical packages
function M.install_sync(python_path, packages)
	local pip_cmd = python_path .. " -m pip"
	
	-- Check if uv is available and preferred
	if config.get().python.use_uv and vim.fn.executable("uv") == 1 then
		pip_cmd = "uv pip"
	end
	
	local install_cmd = pip_cmd .. " install " .. table.concat(packages, " ") .. " 2>&1"
	utils.notify("Installing: " .. table.concat(packages, ", "), vim.log.levels.INFO)
	
	local result = vim.fn.system(install_cmd)
	return vim.v.shell_error == 0, result
end

-- Check and install essential packages
function M.ensure_essentials(force, sync)
	local python_path = M.get_project_python()
	
	if not python_path then
		if not force then
			return false, "No virtual environment found"
		end
		-- Use system Python as fallback
		python_path = vim.fn.exepath("python3") or vim.fn.exepath("python")
		if not python_path then
			return false, "No Python found"
		end
	end
	
	local missing_packages = {}
	
	-- Check which packages are missing
	for _, package in ipairs(M.essential_packages) do
		-- Special handling for package names that differ from import names
		local import_name = package
		if package == "jupytext" then
			import_name = "jupytext"
		elseif package == "jupyter_client" then
			import_name = "jupyter_client"
		elseif package == "ipython" then
			import_name = "IPython"
		end
		
		if not M.is_package_installed(python_path, import_name) then
			table.insert(missing_packages, package)
		end
	end
	
	if #missing_packages == 0 then
		return true, "All essential packages installed"
	end
	
	-- If sync mode requested, install synchronously
	if sync then
		utils.notify("📦 Installing essential packages (this may take a moment)...", vim.log.levels.INFO)
		local success, result = M.install_sync(python_path, missing_packages)
		if success then
			utils.notify("✓ Essential packages installed!", vim.log.levels.INFO)
			return true, "Packages installed"
		else
			utils.notify("Failed to install packages", vim.log.levels.ERROR)
			return false, "Installation failed"
		end
	end
	
	-- Auto-install missing packages
	utils.notify("📦 Installing essential notebook packages: " .. table.concat(missing_packages, ", "), vim.log.levels.INFO)
	
	-- Check if we're already installing (prevent duplicate jobs)
	local job_key = "essential_install_" .. vim.fn.getcwd()
	if config.get_state("jobs." .. job_key) then
		utils.notify("Installation already in progress...", vim.log.levels.INFO)
		return false, "Installation in progress"
	end
	
	-- Mark installation as in progress
	config.set_state("jobs." .. job_key, true)
	
	-- Determine package manager
	local pip_cmd = python_path .. " -m pip"
	
	-- Check if uv is available and preferred
	if config.get().python.use_uv and vim.fn.executable("uv") == 1 then
		-- Use uv for faster installation
		pip_cmd = "uv pip"
	end
	
	-- Install packages
	local install_cmd = pip_cmd .. " install " .. table.concat(missing_packages, " ")
	
	-- Run installation asynchronously
	vim.fn.jobstart(install_cmd, {
		on_exit = function(_, exit_code)
			-- Clear job state
			config.set_state("jobs." .. job_key, nil)
			
			if exit_code == 0 then
				utils.notify("✓ Essential packages installed successfully!", vim.log.levels.INFO)
				
				-- Now ensure kernel exists
				local kernel_mgr = require("pyworks.kernel-manager")
				local success, msg = kernel_mgr.ensure_project_kernel()
				if success then
					utils.notify("✓ Jupyter kernel ready: " .. msg, vim.log.levels.INFO)
				end
			else
				utils.notify("Failed to install some packages - check your network connection", vim.log.levels.WARN)
				utils.notify("You can manually install with: " .. install_cmd, vim.log.levels.INFO)
			end
		end,
		on_stdout = function(_, data)
			-- Optionally show installation progress
			for _, line in ipairs(data) do
				if line ~= "" and (line:match("Successfully installed") or line:match("Requirement already satisfied")) then
					utils.notify("  " .. line, vim.log.levels.INFO)
				end
			end
		end,
		on_stderr = function(_, data)
			-- Show errors
			for _, line in ipairs(data) do
				if line ~= "" and not line:match("WARNING:") then
					utils.notify("  ⚠ " .. line, vim.log.levels.WARN)
				end
			end
		end,
	})
	
	return true, "Installing packages..."
end

-- Check if we should auto-install essentials
function M.should_auto_install()
	-- Check if we're opening a notebook or Python file with Jupyter cells
	local filename = vim.fn.expand("%:t")
	local filetype = vim.bo.filetype
	
	-- Check for notebooks
	if filename:match("%.ipynb$") then
		return true
	end
	
	-- Check for Python files with Jupyter cells
	if filetype == "python" then
		local lines = vim.api.nvim_buf_get_lines(0, 0, math.min(50, vim.api.nvim_buf_line_count(0)), false)
		for _, line in ipairs(lines) do
			if line:match("^# %%") or line:match("^#%%") then
				return true
			end
		end
	end
	
	return false
end

-- Auto-install hook for autocmds
function M.auto_install_hook()
	if M.should_auto_install() then
		M.ensure_essentials()
	end
end

return M