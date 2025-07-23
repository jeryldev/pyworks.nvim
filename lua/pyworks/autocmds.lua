-- pyworks.nvim - Autocmds module
-- Handles automatic commands

local M = {}
local config = require("pyworks.config")
local utils = require("pyworks.utils")

function M.setup(user_config)
	-- Check if venv should be activated on startup
	vim.api.nvim_create_autocmd("VimEnter", {
		pattern = "*",
		callback = function()
			-- Ensure this runs after plugins are loaded
			vim.schedule(function()
				local cwd, venv_path = utils.get_project_paths()

				if vim.fn.isdirectory(venv_path) == 1 then
					local venv_bin = venv_path .. "/bin"
					local python_path = venv_path .. "/bin/python3"
					local current_python = vim.fn.exepath("python3")

					-- Add venv/bin to PATH if not already there
					if not vim.env.PATH:match(vim.pesc(venv_bin)) then
						vim.env.PATH = venv_bin .. ":" .. vim.env.PATH
					end

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
			local cwd, venv_path = utils.get_project_paths()
			if vim.fn.isdirectory(venv_path) == 1 then
				local venv_bin = venv_path .. "/bin"
				local python_path = venv_path .. "/bin/python3"

				-- Add venv/bin to PATH if not already there
				if not vim.env.PATH:match(vim.pesc(venv_bin)) then
					vim.env.PATH = venv_bin .. ":" .. vim.env.PATH
				end

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

				-- Write back the fixed content using vim.json.encode
				local fixed_json = vim.json.encode(notebook)
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(fixed_json, "\n"))
			end
		end,
	})
end

return M
