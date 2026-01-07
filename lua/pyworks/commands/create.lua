-- Commands for creating new notebook files
local M = {}

local jupytext = require("pyworks.notebook.jupytext")
local ui = require("pyworks.ui")

local VENV_CHECK_MAX_ATTEMPTS = 30
local VENV_CHECK_INTERVAL_MS = 1000

-- Helper function to ensure parent directories exist
local function ensure_parent_dirs(filepath)
	local parent = vim.fn.fnamemodify(filepath, ":h")
	if parent ~= "." and parent ~= "" and vim.fn.isdirectory(parent) == 0 then
		local ok = vim.fn.mkdir(parent, "p")
		if ok == 0 then
			vim.notify("Failed to create directory: " .. parent, vim.log.levels.ERROR)
			return false
		end
	end
	return true
end

-- Helper function to validate filename
local function validate_filename(filename, extension)
	-- Check for invalid characters
	if filename:match("[<>:|?*]") then
		vim.notify("Invalid filename: " .. filename, vim.log.levels.ERROR)
		return nil
	end

	-- Ensure correct extension
	if not filename:match("%." .. extension .. "$") then
		filename = filename .. "." .. extension
	end

	-- Convert to absolute path to ensure session restore works correctly
	filename = vim.fn.fnamemodify(filename, ":p")

	-- Ensure parent directories exist
	if not ensure_parent_dirs(filename) then
		return nil
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
		ok, err = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(filename))
		if not ok then
			vim.notify("Failed to create file: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return false
		end
	else
		ok, err = pcall(vim.cmd, "enew")
		if not ok then
			vim.notify("Failed to create new buffer: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return false
		end
	end

	-- Add template content
	ok, err = pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, template_lines)
	if not ok then
		vim.notify("Failed to set template content: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return false
	end

	-- Set filetype for syntax highlighting
	vim.bo.filetype = filetype

	-- Auto-save if filename was provided
	if filename then
		ok, err = pcall(vim.cmd, "write")
		if not ok then
			vim.notify("File created but could not save: " .. (err or "unknown error"), vim.log.levels.WARN)
		end
	end

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
		if filename then
			vim.notify("Created Python notebook: " .. filename, vim.log.levels.INFO)
		else
			vim.notify("Created new Python notebook (use :w to save)", vim.log.levels.INFO)
		end
		ui.enter_first_cell()
	end
end, { nargs = "?", desc = "Create new Python file with cells" })

-- Generate unique cell ID (required in nbformat 4.5+)
local function generate_cell_id()
	math.randomseed(vim.uv.hrtime())
	local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	local id = ""
	for _ = 1, 8 do
		local idx = math.random(1, #chars)
		id = id .. chars:sub(idx, idx)
	end
	return id
end

-- Create notebook JSON structure
local function generate_notebook_json(kernel_info, imports)
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

	local ok, json_str = pcall(vim.json.encode, notebook)
	if not ok then
		return nil, "Failed to create notebook structure: " .. (json_str or "unknown error")
	end
	return json_str, nil
end

-- Write notebook JSON to file
local function write_notebook_file(filename, json_str)
	local file, err = io.open(filename, "w")
	if not file then
		return false, "Failed to create file: " .. (err or "unknown error")
	end

	local write_ok, write_err = pcall(function()
		file:write(json_str)
		file:close()
	end)

	if not write_ok then
		pcall(function()
			file:close()
		end)
		return false, "Failed to write notebook: " .. (write_err or "unknown error")
	end

	return true, nil
end

-- Open notebook and verify jupytext conversion
local function open_and_verify_notebook(filename, language)
	if not jupytext.is_jupytext_installed() then
		vim.notify("Created " .. language .. " notebook: " .. filename, vim.log.levels.INFO)
		vim.notify(" jupytext not installed - cannot open .ipynb files in editor", vim.log.levels.WARN)
		vim.notify("Run :PyworksSetup to create a venv and install jupytext", vim.log.levels.INFO)
		return true
	end

	local open_ok, open_err = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(filename))
	if not open_ok then
		vim.notify("Notebook created but failed to open: " .. (open_err or "unknown error"), vim.log.levels.WARN)
		vim.notify("You can open it manually: " .. filename, vim.log.levels.INFO)
		return true
	end

	-- Check if jupytext conversion worked (buffer should NOT start with '{')
	local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
	if first_line:match("^%s*{") then
		jupytext.configure_jupytext_nvim()
		vim.cmd("edit!")
		local check_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
		if check_line:match("^%s*{") then
			vim.notify("Notebook showing as JSON. Try :edit! to reload.", vim.log.levels.WARN)
		else
			ui.enter_first_cell()
		end
	else
		ui.enter_first_cell()
	end
	vim.notify("Created " .. language .. " notebook: " .. filename, vim.log.levels.INFO)
	return true
end

-- Create .ipynb notebook file
local function create_ipynb_file(filename, language, kernel_info, imports)
	if not filename:match("%.ipynb$") then
		filename = filename .. ".ipynb"
	end

	-- Convert to absolute path to ensure session restore works correctly
	filename = vim.fn.fnamemodify(filename, ":p")

	-- Ensure parent directories exist
	if not ensure_parent_dirs(filename) then
		return false
	end

	if vim.fn.filereadable(filename) == 1 then
		local choice = vim.fn.confirm("File '" .. filename .. "' already exists. Overwrite?", "&Yes\n&No", 2)
		if choice ~= 1 then
			return false
		end
	end

	local json_str, json_err = generate_notebook_json(kernel_info, imports)
	if not json_str then
		vim.notify("" .. json_err, vim.log.levels.ERROR)
		return false
	end

	local write_ok, write_err = write_notebook_file(filename, json_str)
	if not write_ok then
		vim.notify("" .. write_err, vim.log.levels.ERROR)
		return false
	end

	return open_and_verify_notebook(filename, language)
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
		vim.notify("Invalid filename: " .. filename, vim.log.levels.ERROR)
		return
	end

	-- Check for directory traversal attacks
	if filename:match("%.%.") then
		vim.notify("Invalid filename: directory traversal not allowed", vim.log.levels.ERROR)
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
				vim.notify("Setting up Python environment in: " .. cwd, vim.log.levels.INFO)

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
								vim.notify("jupytext installed!", vim.log.levels.INFO)
								-- Re-configure jupytext.nvim to update PATH with venv's bin directory
								jupytext.configure_jupytext_nvim()
								do_create_notebook(filename)
							elseif attempts >= VENV_CHECK_MAX_ATTEMPTS then
								timer:stop()
								timer:close()
								vim.notify("jupytext installation taking too long", vim.log.levels.WARN)
								vim.notify(
									"Creating notebook file anyway (open it once jupytext is ready)",
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
