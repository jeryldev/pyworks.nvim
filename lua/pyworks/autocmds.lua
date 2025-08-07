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
			-- Wait for buffer to be fully loaded and jupytext to process it
			vim.defer_fn(function()
				-- Check if Molten is available
				if vim.fn.exists(":MoltenInit") ~= 2 then
					return
				end
				
				-- Check if kernel is already initialized for this buffer
				if vim.fn.exists("*MoltenRunningKernels") == 1 then
					local buffer_kernels = vim.fn.MoltenRunningKernels(true) or {}
					if #buffer_kernels > 0 then
						-- Kernel already running for this buffer
						return
					end
				end
				
				-- Auto-initialize kernel silently
				local molten = require("pyworks.molten")
				molten.init_kernel(true) -- true for silent mode
				
				-- After kernel init, check for missing packages
				vim.defer_fn(function()
					-- Detect language from notebook
					local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
					local content = table.concat(lines, "\n")
					
					-- Check if it's a Python notebook (most common)
					if content:match("import%s+%w+") or content:match("from%s+%w+") then
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
					elseif content:match("using%s+%w+") then
						-- Julia notebook
						utils.notify("Julia notebook detected - package management coming soon", vim.log.levels.INFO)
					elseif content:match("library%(") or content:match("require%(") then
						-- R notebook
						utils.notify("R notebook detected - package management coming soon", vim.log.levels.INFO)
					end
				end, 2000) -- Wait a bit after kernel init
			end, 1000) -- Wait for jupytext to process
		end,
		desc = "Auto-initialize Jupyter kernel for notebooks",
	})
	
	-- Check for missing packages in Python files
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = pyworks_group,
		pattern = "*.py",
		callback = function()
			-- Only check if we have a venv
			if not utils.has_venv() then
				return
			end
			
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
			end, 500) -- Quick check after file opens
		end,
		desc = "Check for missing Python packages",
	})
	
	-- Auto-initialize kernel for Julia files
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = pyworks_group,
		pattern = "*.jl",
		callback = function()
			-- Check if Molten is available
			if vim.fn.exists(":MoltenInit") ~= 2 then
				return
			end
			
			-- Auto-initialize Julia kernel after a delay
			vim.defer_fn(function()
				-- Check if kernel is already initialized
				if vim.fn.exists("*MoltenRunningKernels") == 1 then
					local buffer_kernels = vim.fn.MoltenRunningKernels(true) or {}
					if #buffer_kernels > 0 then
						return -- Already initialized
					end
				end
				
				-- Initialize Julia kernel
				utils.notify("Detected Julia file - auto-initializing kernel...", vim.log.levels.INFO)
				local molten = require("pyworks.molten")
				molten.init_kernel(true) -- Silent mode
				
				-- Julia package detection (future enhancement)
				local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
				local content = table.concat(lines, "\n")
				if content:match("using%s+%w+") or content:match("import%s+%w+") then
					vim.defer_fn(function()
						utils.notify("Julia package management coming soon!", vim.log.levels.INFO)
						utils.notify("Use Pkg.add() in Julia REPL for now", vim.log.levels.INFO)
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
			-- Check if Molten is available
			if vim.fn.exists(":MoltenInit") ~= 2 then
				return
			end
			
			-- Auto-initialize R kernel after a delay
			vim.defer_fn(function()
				-- Check if kernel is already initialized
				if vim.fn.exists("*MoltenRunningKernels") == 1 then
					local buffer_kernels = vim.fn.MoltenRunningKernels(true) or {}
					if #buffer_kernels > 0 then
						return -- Already initialized
					end
				end
				
				-- Initialize R kernel
				utils.notify("Detected R file - auto-initializing kernel...", vim.log.levels.INFO)
				local molten = require("pyworks.molten")
				molten.init_kernel(true) -- Silent mode
				
				-- R package detection (future enhancement)
				local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
				local content = table.concat(lines, "\n")
				if content:match("library%(") or content:match("require%(") then
					vim.defer_fn(function()
						utils.notify("R package management coming soon!", vim.log.levels.INFO)
						utils.notify("Use install.packages() in R console for now", vim.log.levels.INFO)
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
