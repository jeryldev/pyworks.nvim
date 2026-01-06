-- Commands for creating new notebook files
local M = {}

local jupytext = require("pyworks.notebook.jupytext")

local VENV_CHECK_MAX_ATTEMPTS = 30
local VENV_CHECK_INTERVAL_MS = 1000

-- Helper function to position cursor below first cell marker
local function position_cursor_at_first_cell()
	-- Find first cell marker (# %% for Python, or markdown marker)
	vim.cmd("normal! gg")
	local found = vim.fn.search("^# %%", "W")
	if found > 0 then
		-- Move to line below the marker
		local next_line = found + 1
		local last_line = vim.api.nvim_buf_line_count(0)
		if next_line <= last_line then
			vim.api.nvim_win_set_cursor(0, { next_line, 0 })
		end
	end
end

-- Helper function to validate filename
local function validate_filename(filename, extension)
	-- Check for invalid characters
	if filename:match("[<>:|?*]") then
		vim.notify("❌ Invalid filename: " .. filename, vim.log.levels.ERROR)
		return nil
	end

	-- Ensure correct extension
	if not filename:match("%." .. extension .. "$") then
		filename = filename .. "." .. extension
	end

	-- Check if file already exists
	if vim.fn.filereadable(filename) == 1 then
		local choice = vim.fn.confirm("File '" .. filename .. "' already exists. Overwrite?", "&Yes\n&No", 2)
		if choice ~= 1 then
			return nil
		end
	end

	return filename
end

-- Helper function to create file with template
local function create_file_with_template(filename, template_lines, filetype)
	local ok, err

	-- Create or open file
	if filename then
		ok, err = pcall(vim.cmd, "edit " .. filename)
		if not ok then
			vim.notify("❌ Failed to create file: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return false
		end
	else
		ok, err = pcall(vim.cmd, "enew")
		if not ok then
			vim.notify("❌ Failed to create new buffer: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return false
		end
	end

	-- Add template content
	ok, err = pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, template_lines)
	if not ok then
		vim.notify("❌ Failed to set template content: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return false
	end

	-- Set filetype for syntax highlighting
	vim.bo.filetype = filetype

	return true
end

-- Create a new Python file with cell markers
vim.api.nvim_create_user_command("PyworksNewPython", function(opts)
	local filename = opts.args ~= "" and opts.args or nil

	-- Validate filename if provided
	if filename then
		filename = validate_filename(filename, "py")
		if not filename then
			return
		end
	end

	-- Template content
	local template = {
		"# %%",
		"import numpy as np",
		"import pandas as pd",
		"import matplotlib.pyplot as plt",
		"",
		"# %%",
		"",
	}

	-- Create file with template
	if create_file_with_template(filename, template, "python") then
		position_cursor_at_first_cell()
		if filename then
			vim.notify("✅ Created Python notebook: " .. filename, vim.log.levels.INFO)
		else
			vim.notify("✅ Created new Python notebook (use :w to save)", vim.log.levels.INFO)
		end
	end
end, { nargs = "?", desc = "Create new Python file with cells" })

-- Helper function to create .ipynb files
local function create_ipynb_file(filename, language, kernel_info, imports)
	-- Ensure .ipynb extension
	if not filename:match("%.ipynb$") then
		filename = filename .. ".ipynb"
	end

	-- Check if file already exists
	if vim.fn.filereadable(filename) == 1 then
		local choice = vim.fn.confirm("File '" .. filename .. "' already exists. Overwrite?", "&Yes\n&No", 2)
		if choice ~= 1 then
			return false
		end
	end

	-- Generate unique cell IDs (required in nbformat 4.5+)
	local function generate_cell_id()
		local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
		local id = ""
		for i = 1, 8 do
			local idx = math.random(1, #chars)
			id = id .. chars:sub(idx, idx)
		end
		return id
	end

	-- Create notebook JSON structure
	local notebook = {
		cells = {
			{
				cell_type = "code",
				execution_count = vim.NIL,
				id = generate_cell_id(),
				metadata = vim.empty_dict(),
				outputs = {},
				source = imports,
			},
			{
				cell_type = "code",
				execution_count = vim.NIL,
				id = generate_cell_id(),
				metadata = vim.empty_dict(),
				outputs = {},
				source = {},
			},
		},
		metadata = kernel_info,
		nbformat = 4,
		nbformat_minor = 5,
	}

	-- Try to encode JSON
	local ok, json_str = pcall(vim.json.encode, notebook)
	if not ok then
		vim.notify("❌ Failed to create notebook structure: " .. (json_str or "unknown error"), vim.log.levels.ERROR)
		return false
	end

	-- Write to file
	local file, err = io.open(filename, "w")
	if not file then
		vim.notify("❌ Failed to create file: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return false
	end

	local write_ok, write_err = pcall(function()
		file:write(json_str)
		file:close()
	end)

	if not write_ok then
		vim.notify("❌ Failed to write notebook: " .. (write_err or "unknown error"), vim.log.levels.ERROR)
		pcall(function()
			file:close()
		end)
		return false
	end

	-- Check if jupytext is available before trying to open
	if not jupytext.is_jupytext_installed() then
		vim.notify("✅ Created " .. language .. " notebook: " .. filename, vim.log.levels.INFO)
		vim.notify("⚠️  jupytext not installed - cannot open .ipynb files in editor", vim.log.levels.WARN)
		vim.notify("💡 Run :PyworksSetup to create a venv and install jupytext", vim.log.levels.INFO)
		return true
	end

	-- Open the file (jupytext is available)
	local open_ok, open_err = pcall(vim.cmd, "edit " .. filename)
	if not open_ok then
		vim.notify("⚠️ Notebook created but failed to open: " .. (open_err or "unknown error"), vim.log.levels.WARN)
		vim.notify("You can open it manually: " .. filename, vim.log.levels.INFO)
		return true
	end

	-- Position cursor at first cell (defer to allow jupytext to finish converting)
	vim.defer_fn(function()
		position_cursor_at_first_cell()
	end, 100)

	vim.notify("✅ Created " .. language .. " notebook: " .. filename, vim.log.levels.INFO)
	return true
end

-- Helper to create notebook after environment is ready
local function do_create_notebook(filename)
	local kernel_info = {
		kernelspec = {
			display_name = "Python 3",
			language = "python",
			name = "python3",
		},
		language_info = {
			name = "python",
			version = "3.12.0",
		},
	}

	local imports = {
		"import numpy as np\n",
		"import pandas as pd\n",
		"import matplotlib.pyplot as plt",
	}

	-- Invalidate jupytext cache before creating (in case we just installed it)
	local cache = require("pyworks.core.cache")
	cache.invalidate("jupytext_check")

	create_ipynb_file(filename, "Python", kernel_info, imports)
end

-- Create a new Python .ipynb notebook
vim.api.nvim_create_user_command("PyworksNewPythonNotebook", function(opts)
	local filename = opts.args ~= "" and opts.args or "notebook"

	-- Check for invalid characters
	if filename:match("[<>:|?*]") then
		vim.notify("❌ Invalid filename: " .. filename, vim.log.levels.ERROR)
		return
	end

	-- Check for directory traversal attacks
	if filename:match("%.%.") then
		vim.notify("❌ Invalid filename: directory traversal not allowed", vim.log.levels.ERROR)
		return
	end

	-- Check if jupytext is available
	if not jupytext.is_jupytext_installed() then
		-- Offer to set up environment first using vim.ui.select for nice UI
		vim.ui.select({
			"Yes - Set up environment first (recommended)",
			"No - Create file only (can't open yet)",
			"Cancel",
		}, {
			prompt = "jupytext not found. Set up Python environment?",
		}, function(choice)
			if choice == "Yes - Set up environment first (recommended)" then
				-- Set up environment, then create notebook
				local cwd = vim.fn.getcwd()
				vim.notify("📁 Setting up Python environment in: " .. cwd, vim.log.levels.INFO)

				local python = require("pyworks.languages.python")
				local error_handler = require("pyworks.core.error_handler")
				local cache = require("pyworks.core.cache")
				local dummy_filepath = cwd .. "/setup.py"

				local ok = error_handler.protected_call(python.ensure_environment, "Setup failed", dummy_filepath)
				if ok then
					-- Poll for jupytext availability (installed as part of essentials), then create notebook
					local attempts = 0
					local timer = vim.uv.new_timer()

					timer:start(
						VENV_CHECK_INTERVAL_MS,
						VENV_CHECK_INTERVAL_MS,
						vim.schedule_wrap(function()
							attempts = attempts + 1
							cache.invalidate("jupytext_check") -- Clear cache to recheck

							if jupytext.is_jupytext_installed() then
								timer:stop()
								timer:close()
								vim.notify("✅ jupytext installed!", vim.log.levels.INFO)
								-- Re-configure jupytext.nvim to update PATH with venv's bin directory
								jupytext.configure_jupytext_nvim()
								do_create_notebook(filename)
							elseif attempts >= VENV_CHECK_MAX_ATTEMPTS then
								timer:stop()
								timer:close()
								vim.notify("⚠️  jupytext installation taking too long", vim.log.levels.WARN)
								vim.notify(
									"📁 Creating notebook file anyway (open it once jupytext is ready)",
									vim.log.levels.INFO
								)
								do_create_notebook(filename)
							end
						end)
					)
				end
			elseif choice == "No - Create file only (can't open yet)" then
				-- Create file only (can't open it)
				vim.notify(
					"Creating notebook file (won't be able to open until jupytext is installed)...",
					vim.log.levels.INFO
				)
				do_create_notebook(filename)
			end
			-- Cancel or nil choice: do nothing
		end)
		return
	end

	do_create_notebook(filename)
end, { nargs = "?", desc = "Create new Python .ipynb notebook" })

return M
