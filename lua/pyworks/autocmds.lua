-- pyworks.nvim - Autocmds module
-- Handles automatic commands

local M = {}

function M.setup(config)
	-- Check if venv should be activated on startup
	vim.api.nvim_create_autocmd("VimEnter", {
		pattern = "*",
		callback = function()
			local venv_path = vim.fn.getcwd() .. "/.venv"
			if vim.fn.isdirectory(venv_path) == 1 then
				local current_python = vim.fn.exepath("python3")
				if not current_python:match(venv_path) then
					vim.notify("⚠️  Virtual environment not activated!", vim.log.levels.WARN)
					vim.notify("Run in terminal: source .venv/bin/activate", vim.log.levels.INFO)
					vim.notify("Note: Neovim will still use the correct Python for notebooks", vim.log.levels.INFO)
				end
			end
		end,
		desc = "Check if virtual environment is activated",
	})

	-- Auto-activate virtual environment in terminal
	if config.auto_activate_venv then
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

