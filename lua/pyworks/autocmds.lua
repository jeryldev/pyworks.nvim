-- pyworks.nvim - Autocmds module
-- Handles automatic commands

local M = {}
local config = require("pyworks.config")
local utils = require("pyworks.utils")

function M.setup(user_config)
	-- Create augroup for pyworks
	local pyworks_group = vim.api.nvim_create_augroup("PyworksAutocmds", { clear = true })
	
	-- Check if venv should be activated on startup
	vim.api.nvim_create_autocmd("VimEnter", {
		pattern = "*",
		callback = function()
			-- Ensure this runs after plugins are loaded
			vim.schedule(function()
				if utils.has_venv() then
					local _, venv_path = utils.get_project_paths()
					local python_path = utils.get_python_path()
					local current_python = vim.fn.exepath("python3")

					-- Add venv/bin to PATH if not already there
					utils.ensure_venv_in_path()

					-- Always set Python host
					vim.g.python3_host_prog = python_path
					config.set_state("venv.python_path", python_path)
					config.update_venv_state(venv_path)

					-- Only show the warning if the venv isn't being used at all
					if not current_python:match(venv_path) and not vim.env.PATH:match(venv_path) then
						vim.notify(
							"💡 Tip: You can activate the venv in your shell with: source .venv/bin/activate",
							vim.log.levels.INFO
						)
					else
						-- Silently confirm everything is set up correctly
						vim.cmd("silent! doautocmd User PyworksVenvActivated")
					end
				end
			end) -- End of vim.schedule
		end,
		desc = "Check if virtual environment is activated, add to PATH, and set Python host",
	})

	-- Also check when changing directories
	vim.api.nvim_create_autocmd("DirChanged", {
		pattern = "*",
		callback = function()
			if utils.has_venv() then
				local _, venv_path = utils.get_project_paths()
				local python_path = utils.get_python_path()

				-- Add venv/bin to PATH if not already there
				utils.ensure_venv_in_path()

				-- Update Python host to match current directory's venv
				vim.g.python3_host_prog = python_path
				config.set_state("venv.python_path", python_path)
				config.update_venv_state(venv_path)
			end
		end,
		desc = "Update PATH and Python host when changing directories",
	})

	-- Auto-activate virtual environment in terminal
	if user_config.auto_activate_venv then
		vim.api.nvim_create_autocmd("TermOpen", {
			pattern = "*",
			callback = function()
				-- Check if we have a .venv in the current directory
				local venv_activate = vim.fn.getcwd() .. "/.venv/bin/activate"
				if vim.fn.filereadable(venv_activate) == 1 then
					-- Get the current buffer number
					local bufnr = vim.api.nvim_get_current_buf()
					-- Send the activation command to the terminal
					local chan = vim.b[bufnr].terminal_job_id
					if chan then
						-- Deactivate any existing virtual environment
						-- Handle different virtual environment types:

						-- 1. Standard venv/virtualenv (uses 'deactivate' function)
						vim.api.nvim_chan_send(chan, "deactivate 2>/dev/null || true\n")

						-- 2. Conda environments
						vim.api.nvim_chan_send(
							chan,
							"command -v conda >/dev/null 2>&1 && conda deactivate 2>/dev/null || true\n"
						)

						-- 3. pyenv-virtualenv
						vim.api.nvim_chan_send(
							chan,
							"command -v pyenv >/dev/null 2>&1 && pyenv deactivate 2>/dev/null || true\n"
						)

						-- 4. Poetry shells (exit poetry shell if in one)
						vim.api.nvim_chan_send(chan, "[[ $POETRY_ACTIVE ]] && exit 2>/dev/null || true\n")

						-- 5. pipenv shells (check for PIPENV_ACTIVE)
						vim.api.nvim_chan_send(chan, "[[ $PIPENV_ACTIVE ]] && exit 2>/dev/null || true\n")

						-- Now activate the project venv
						vim.api.nvim_chan_send(chan, "source " .. venv_activate .. "\n")
						-- Clear the terminal for a clean start
						vim.api.nvim_chan_send(chan, "clear\n")
					end
				end
			end,
			desc = "Auto-activate project virtual environment in terminal",
		})
	end

	-- Pre-process notebooks to add missing metadata
	-- This runs BEFORE the file is actually read
	vim.api.nvim_create_autocmd("BufReadPre", {
		group = pyworks_group,
		pattern = "*.ipynb",
		callback = function()
			local filepath = vim.fn.expand("<afile>:p")
			-- Pre-processing notebook
			
			-- Ensure the jupytext-fix module is available
			local ok, fixer = pcall(require, "pyworks.jupytext-fix")
			if ok then
				local fixed = fixer.fix_notebook_metadata(filepath)
				if fixed then
					-- Silently fixed notebook metadata
				end
			else
				-- Fallback inline fix
				local file = io.open(filepath, "r")
				if not file then
					return
				end
				local content = file:read("*all")
				file:close()

				-- Try to parse as JSON
				local json_ok, notebook = pcall(vim.json.decode, content)
				if json_ok and notebook then
					local needs_update = false

					-- Ensure metadata exists
					if not notebook.metadata then
						notebook.metadata = {}
						needs_update = true
					end

					-- Add Python language_info if missing
					if not notebook.metadata.language_info or not notebook.metadata.language_info.name then
						notebook.metadata.language_info = {
							codemirror_mode = {
								name = "ipython",
								version = 3,
							},
							file_extension = ".py",
							mimetype = "text/x-python",
							name = "python",
							nbconvert_exporter = "python",
							pygments_lexer = "ipython3",
							version = "3.11.0",
						}
						needs_update = true
					end

					-- Add Python kernelspec if missing
					if not notebook.metadata.kernelspec or not notebook.metadata.kernelspec.language then
						notebook.metadata.kernelspec = {
							display_name = "Python 3",
							language = "python",
							name = "python3",
						}
						needs_update = true
					end

					-- Write back to file if updated
					if needs_update then
						local fixed_json = vim.json.encode(notebook)
						local write_file = io.open(filepath, "w")
						if write_file then
							write_file:write(fixed_json)
							write_file:close()
							-- Silently fixed notebook metadata
						end
					end
				end
			end
		end,
		desc = "Fix notebook metadata before jupytext processes it",
	})

	-- Auto-initialize Jupyter kernel when opening notebooks
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = pyworks_group,
		pattern = "*.ipynb",
		callback = function()
			-- First, ensure essential packages are installed
			local essentials = require("pyworks.notebook-essentials")
			local success, msg = essentials.ensure_essentials()
			
			-- If packages are being installed, delay kernel init
			if msg == "Installing packages..." then
				utils.notify("Installing essential notebook packages first...", vim.log.levels.INFO)
				-- Wait longer for packages to install
				vim.defer_fn(function()
					-- Now try kernel initialization
					if vim.g.molten_error_detected or vim.env.PYWORKS_NO_MOLTEN then
						utils.notify("Kernel support disabled - package detection only", vim.log.levels.INFO)
						return
					end
					
					-- Re-check and initialize kernel
					utils.notify("Packages installed, initializing kernel...", vim.log.levels.INFO)
					local molten = require("pyworks.molten")
					molten.init_kernel()
				end, 5000) -- Wait 5 seconds for package installation
				return
			end
			
			-- Wait for buffer to be fully loaded and jupytext to process it
			vim.defer_fn(function()
				-- Skip Molten entirely if there's an error or disable flag
				if vim.g.molten_error_detected or vim.env.PYWORKS_NO_MOLTEN then
					utils.notify("Kernel support disabled - package detection only", vim.log.levels.INFO)
				else
					-- Show detection immediately
					utils.notify("Detected notebook - checking for compatible kernel...", vim.log.levels.INFO)
				end
				
				-- Check if Molten is available and properly setup
				if vim.fn.exists(":MoltenInit") == 2 and not vim.g.pyworks_needs_restart and not vim.g.molten_error_detected then
					-- Check if kernel is already initialized for this buffer
					if vim.fn.exists("*MoltenRunningKernels") == 1 then
						local buffer_kernels = vim.fn.MoltenRunningKernels(true) or {}
						if #buffer_kernels == 0 then
							-- Auto-initialize kernel
							local molten = require("pyworks.molten")
							molten.init_kernel() -- Show full notifications
						else
							utils.notify("Kernel already running for this notebook", vim.log.levels.INFO)
						end
					else
						-- Try to init anyway
						local molten = require("pyworks.molten")
						molten.init_kernel() -- Show full notifications
					end
				else
					-- Molten not available, but still continue with package detection
					utils.notify("Jupyter kernel support not available - install Molten for notebook features", vim.log.levels.INFO)
				end
				
				-- ALWAYS check for missing packages (regardless of Molten)
				vim.defer_fn(function()
					-- Detect language from notebook
					local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
					local content = table.concat(lines, "\n")
					
					-- Check if it's a Python notebook (most common)
					if content:match("import%s+%w+") or content:match("from%s+%w+") then
						if utils.has_venv() then
							local detector = require("pyworks.package-detector")
							local result = detector.analyze_buffer()
							
							if result and #result.missing > 0 then
								utils.notify("📦 Missing packages: " .. table.concat(result.missing, ", "), vim.log.levels.WARN)
								-- Make the install hint more prominent
								vim.defer_fn(function()
									utils.notify("=====================================", vim.log.levels.INFO)
									utils.notify(">>> Press <leader>pi to install missing packages", vim.log.levels.WARN)
									utils.notify("=====================================", vim.log.levels.INFO)
								end, 100) -- Small delay to ensure it appears after other messages
							end
						else
							utils.notify("No virtual environment found - run :PyworksSetup to create one", vim.log.levels.INFO)
						end
					elseif content:match("using%s+%w+") then
						-- Julia notebook
						local julia_packages = {}
						for package in content:gmatch("using%s+([%w%.]+)") do
							table.insert(julia_packages, package)
						end
						for package in content:gmatch("import%s+([%w%.]+)") do
							table.insert(julia_packages, package)
						end
						if #julia_packages > 0 then
							utils.notify("📦 Detected Julia packages: " .. table.concat(julia_packages, ", "), vim.log.levels.INFO)
							utils.notify("Julia package installation coming soon - use Pkg.add() for now", vim.log.levels.INFO)
						end
					elseif content:match("library%(") or content:match("require%(") then
						-- R notebook
						local r_packages = {}
						for package in content:gmatch("library%s*%([\"\']?([%w%.]+)") do
							table.insert(r_packages, package)
						end
						for package in content:gmatch("require%s*%([\"\']?([%w%.]+)") do
							table.insert(r_packages, package)
						end
						if #r_packages > 0 then
							utils.notify("📦 Detected R packages: " .. table.concat(r_packages, ", "), vim.log.levels.INFO)
							utils.notify("R package installation coming soon - use install.packages() for now", vim.log.levels.INFO)
						end
					end
				end, 1500) -- Wait a bit
			end, 1000) -- Wait for jupytext to process
		end,
		desc = "Auto-initialize Jupyter kernel for notebooks",
	})
	
	-- Auto-initialize kernel and check packages for Python files
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = pyworks_group,
		pattern = "*.py",
		callback = function()
			-- Check if this Python file has Jupyter cells
			local has_cells = false
			local lines = vim.api.nvim_buf_get_lines(0, 0, math.min(50, vim.api.nvim_buf_line_count(0)), false)
			for _, line in ipairs(lines) do
				if line:match("^# %%") or line:match("^#%%") then
					has_cells = true
					break
				end
			end
			
			-- If it has cells, ensure essentials are installed
			if has_cells then
				local essentials = require("pyworks.notebook-essentials")
				essentials.ensure_essentials()
			end
			
			-- Skip entirely if Molten is disabled
			if vim.g.molten_error_detected or vim.env.PYWORKS_NO_MOLTEN then
				-- Just do package detection
				if utils.has_venv() then
					vim.defer_fn(function()
						local detector = require("pyworks.package-detector")
						local result = detector.analyze_buffer()
						
						if result and #result.missing > 0 then
							utils.notify("📦 Missing packages: " .. table.concat(result.missing, ", "), vim.log.levels.WARN)
							utils.notify(">>> Press <leader>pi to install missing packages", vim.log.levels.WARN)
						end
					end, 1000)
				end
				return  -- Exit early, skip all Molten stuff
			end
			
			-- Show detection immediately
			utils.notify("Detected Python file - checking for Jupyter support...", vim.log.levels.INFO)
			
			vim.defer_fn(function()
				-- Check if Molten is available and properly setup
				if vim.fn.exists(":MoltenInit") == 2 and not vim.g.pyworks_needs_restart and not vim.g.molten_error_detected then
					-- Molten is available, try to initialize kernel
					-- Check if kernel is already initialized
					if vim.fn.exists("*MoltenRunningKernels") == 1 then
						local buffer_kernels = vim.fn.MoltenRunningKernels(true) or {}
						if #buffer_kernels == 0 then
							-- Auto-initialize Python kernel with notifications
							utils.notify("Checking for compatible Python kernel...", vim.log.levels.INFO)
							local molten = require("pyworks.molten")
							molten.init_kernel() -- Show full notifications
						else
							utils.notify("Python kernel already running", vim.log.levels.INFO)
						end
					else
						-- Molten exists but MoltenRunningKernels doesn't - try to init anyway
						utils.notify("Initializing Python kernel...", vim.log.levels.INFO)
						local molten = require("pyworks.molten")
						molten.init_kernel() -- Show full notifications
					end
				else
					-- Molten not available, but still continue with package detection
					utils.notify("Jupyter kernel support not available - install Molten for notebook features", vim.log.levels.INFO)
				end
				
				-- ALWAYS check for missing packages if we have a venv (regardless of Molten)
				if utils.has_venv() then
					vim.defer_fn(function()
						local detector = require("pyworks.package-detector")
						local result = detector.analyze_buffer()
						
						if result and #result.missing > 0 then
							utils.notify("📦 Missing packages: " .. table.concat(result.missing, ", "), vim.log.levels.WARN)
							
							-- Check for compatibility issues
							if #result.compatibility > 0 then
								for _, issue in ipairs(result.compatibility) do
									utils.notify("⚠️ " .. issue.package .. ": " .. issue.message, vim.log.levels.WARN)
								end
							end
							
							-- Make the install hint more prominent
							vim.defer_fn(function()
								utils.notify("=====================================", vim.log.levels.INFO)
								utils.notify(">>> Press <leader>pi to install missing packages", vim.log.levels.WARN)
								utils.notify("=====================================", vim.log.levels.INFO)
							end, 100) -- Small delay to ensure it appears after other messages
						end
					end, 1000) -- Wait a bit before checking packages
				else
					-- No venv found, suggest creating one
					utils.notify("No virtual environment found - run :PyworksSetup to create one", vim.log.levels.INFO)
				end
			end, 500) -- Initial delay
		end,
		desc = "Auto-initialize kernel and check packages for Python files",
	})
	
	-- Auto-initialize kernel for Julia files
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = pyworks_group,
		pattern = "*.jl",
		callback = function()
			-- Skip entirely if Molten is disabled
			if vim.g.molten_error_detected or vim.env.PYWORKS_NO_MOLTEN then
				utils.notify("Kernel support disabled - Julia file detected", vim.log.levels.INFO)
				return
			end
			
			-- Show detection immediately
			utils.notify("Detected Julia file - checking for Jupyter support...", vim.log.levels.INFO)
			
			vim.defer_fn(function()
				-- Check if Molten is available and properly setup
				if vim.fn.exists(":MoltenInit") == 2 and not vim.g.pyworks_needs_restart then
					-- Check if kernel is already initialized
					if vim.fn.exists("*MoltenRunningKernels") == 1 then
						local buffer_kernels = vim.fn.MoltenRunningKernels(true) or {}
						if #buffer_kernels > 0 then
							utils.notify("Julia kernel already running", vim.log.levels.INFO)
						else
							-- Initialize Julia kernel with notifications
							utils.notify("Checking for compatible Julia kernel...", vim.log.levels.INFO)
							local molten = require("pyworks.molten")
							molten.init_kernel() -- Show full notifications
						end
					else
						-- Try to init anyway
						utils.notify("Initializing Julia kernel...", vim.log.levels.INFO)
						local molten = require("pyworks.molten")
						molten.init_kernel() -- Show full notifications
					end
				else
					-- Molten not available, but still show package info
					utils.notify("Jupyter kernel support not available - install Molten for notebook features", vim.log.levels.INFO)
				end
				
				-- Julia package detection
				local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
				local content = table.concat(lines, "\n")
				local julia_packages = {}
				
				-- Find using statements
				for package in content:gmatch("using%s+([%w%.]+)") do
					table.insert(julia_packages, package)
				end
				-- Find import statements  
				for package in content:gmatch("import%s+([%w%.]+)") do
					table.insert(julia_packages, package)
				end
				
				if #julia_packages > 0 then
					vim.defer_fn(function()
						utils.notify("📦 Detected Julia packages: " .. table.concat(julia_packages, ", "), vim.log.levels.INFO)
						utils.notify("Julia package installation coming soon - use Pkg.add() for now", vim.log.levels.INFO)
					end, 1000)
				end
			end, 1000)
		end,
		desc = "Auto-initialize Julia kernel",
	})
	
	-- Auto-initialize kernel for R files
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = pyworks_group,
		pattern = "*.R",
		callback = function()
			-- Skip entirely if Molten is disabled
			if vim.g.molten_error_detected or vim.env.PYWORKS_NO_MOLTEN then
				utils.notify("Kernel support disabled - R file detected", vim.log.levels.INFO)
				return
			end
			
			-- Show detection immediately
			utils.notify("Detected R file - checking for Jupyter support...", vim.log.levels.INFO)
			
			vim.defer_fn(function()
				-- Check if Molten is available and properly setup
				if vim.fn.exists(":MoltenInit") == 2 and not vim.g.pyworks_needs_restart then
					-- Check if kernel is already initialized
					if vim.fn.exists("*MoltenRunningKernels") == 1 then
						local buffer_kernels = vim.fn.MoltenRunningKernels(true) or {}
						if #buffer_kernels > 0 then
							utils.notify("R kernel already running", vim.log.levels.INFO)
						else
							-- Initialize R kernel with notifications
							utils.notify("Checking for compatible R kernel...", vim.log.levels.INFO)
							local molten = require("pyworks.molten")
							molten.init_kernel() -- Show full notifications
						end
					else
						-- Try to init anyway
						utils.notify("Initializing R kernel...", vim.log.levels.INFO)
						local molten = require("pyworks.molten")
						molten.init_kernel() -- Show full notifications
					end
				else
					-- Molten not available, but still show package info
					utils.notify("Jupyter kernel support not available - install Molten for notebook features", vim.log.levels.INFO)
				end
				
				-- R package detection
				local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
				local content = table.concat(lines, "\n")
				local r_packages = {}
				
				-- Find library() calls
				for package in content:gmatch("library%s*%([\"\']?([%w%.]+)") do
					table.insert(r_packages, package)
				end
				-- Find require() calls
				for package in content:gmatch("require%s*%([\"\']?([%w%.]+)") do
					table.insert(r_packages, package)
				end
				
				if #r_packages > 0 then
					vim.defer_fn(function()
						utils.notify("📦 Detected R packages: " .. table.concat(r_packages, ", "), vim.log.levels.INFO)
						utils.notify("R package installation coming soon - use install.packages() for now", vim.log.levels.INFO)
					end, 1000)
				end
			end, 1000)
		end,
		desc = "Auto-initialize R kernel",
	})
	
	-- Prevent notebook corruption on save
	vim.api.nvim_create_autocmd("BufWritePre", {
		pattern = "*.ipynb",
		callback = function()
			local bufnr = vim.api.nvim_get_current_buf()
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local content = table.concat(lines, "\n")

			-- Try to parse as JSON
			local ok, notebook = pcall(vim.json.decode, content)
			if ok and notebook.cells then
				-- Ensure all cells have required fields
				for i, cell in ipairs(notebook.cells) do
					if not cell.cell_type then
						-- If cell_type is missing, try to infer it
						if cell.source and type(cell.source) == "table" then
							-- Default to code cell if it has outputs field
							cell.cell_type = cell.outputs and "code" or "markdown"
						else
							cell.cell_type = "code" -- Default to code
						end
					end

					-- Ensure code cells have required fields
					if cell.cell_type == "code" then
						cell.outputs = cell.outputs or {}
						cell.execution_count = cell.execution_count or vim.NIL
						cell.metadata = cell.metadata or {}
					end
				end

				-- Ensure metadata has language info for jupytext
				if not notebook.metadata then
					notebook.metadata = {}
				end
				if not notebook.metadata.language_info or not notebook.metadata.language_info.name then
					notebook.metadata.language_info = {
						codemirror_mode = {
							name = "ipython",
							version = 3,
						},
						file_extension = ".py",
						mimetype = "text/x-python",
						name = "python",
						nbconvert_exporter = "python",
						pygments_lexer = "ipython3",
						version = "3.11.0",
					}
				end
				if not notebook.metadata.kernelspec or not notebook.metadata.kernelspec.language then
					notebook.metadata.kernelspec = {
						display_name = "Python 3",
						language = "python",
						name = "python3",
					}
				end

				-- Write back the fixed content using vim.json.encode
				local fixed_json = vim.json.encode(notebook)
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(fixed_json, "\n"))
			end
		end,
	})
end

return M
