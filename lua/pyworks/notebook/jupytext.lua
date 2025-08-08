-- Jupytext integration for notebook viewing
-- Converts .ipynb JSON to readable format

local M = {}

local cache = require("pyworks.core.cache")
local notifications = require("pyworks.core.notifications")
local state = require("pyworks.core.state")
local utils = require("pyworks.utils")

-- Check if jupytext is installed
function M.is_jupytext_installed()
	-- Check cache first
	local cached = cache.get("jupytext_check")
	if cached ~= nil then
		return cached
	end

	-- Check for jupytext
	local python_path = M.get_python_for_jupytext()
	if not python_path then
		cache.set("jupytext_check", false)
		return false
	end

	local cmd = string.format("%s -c 'import jupytext' 2>/dev/null", python_path)
	local result = vim.fn.system(cmd)
	local success = vim.v.shell_error == 0

	-- Cache the result
	cache.set("jupytext_check", success)

	return success
end

-- Get Python interpreter for jupytext
function M.get_python_for_jupytext(filepath)
	-- Get project-specific paths
	local project_dir, venv_path = utils.get_project_paths(filepath)

	-- First try project venv
	if vim.fn.isdirectory(venv_path) == 1 then
		local venv_python = venv_path .. "/bin/python"
		if vim.fn.executable(venv_python) == 1 then
			return venv_python
		end
	end

	-- Try system Python
	if vim.fn.executable("python3") == 1 then
		return "python3"
	end

	if vim.fn.executable("python") == 1 then
		return "python"
	end

	return nil
end

-- Install jupytext
function M.install_jupytext(filepath)
	local python_path = M.get_python_for_jupytext(filepath)
	if not python_path then
		notifications.notify_error("Python not found. Cannot install jupytext.")
		return false
	end

	notifications.progress_start("jupytext_install", "Installing Jupytext", "Installing notebook viewer...")

	-- Determine pip command based on project
	local project_dir, venv_path = utils.get_project_paths(filepath)
	local pip_cmd
	if python_path:match(venv_path) then
		pip_cmd = venv_path .. "/bin/pip"
	else
		pip_cmd = python_path .. " -m pip"
	end

	local cmd = string.format("%s install jupytext", pip_cmd)

	vim.fn.jobstart(cmd, {
		on_exit = function(_, code)
			if code == 0 then
				cache.invalidate("jupytext_check")
				notifications.progress_finish("jupytext_install", "Jupytext installed successfully")
				state.set("persistent_jupytext_installed", true)
			else
				notifications.progress_finish("jupytext_install")
				notifications.notify_error("Failed to install jupytext")
			end
		end,
	})

	return true
end

-- Ensure jupytext is available
function M.ensure_jupytext(filepath)
	if M.is_jupytext_installed() then
		return true -- Already installed, nothing to do
	end

	-- Jupytext is part of Python essentials, so it should be auto-installed
	-- with the Python environment. If it's still missing, install it silently
	M.install_jupytext(filepath)

	-- Return false since installation is async, will be ready later
	return false
end

-- Convert notebook to markdown
function M.notebook_to_markdown(filepath)
	local python_path = M.get_python_for_jupytext()
	if not python_path then
		return nil, "Python not found"
	end

	if not M.is_jupytext_installed() then
		return nil, "Jupytext not installed"
	end

	-- Use jupytext to convert to markdown
	local cmd = string.format("%s -m jupytext --to markdown --output - '%s' 2>/dev/null", python_path, filepath)

	local output = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		return nil, "Failed to convert notebook"
	end

	return output, nil
end

-- Convert notebook to Python script
function M.notebook_to_python(filepath)
	local python_path = M.get_python_for_jupytext()
	if not python_path then
		return nil, "Python not found"
	end

	if not M.is_jupytext_installed() then
		return nil, "Jupytext not installed"
	end

	-- Use jupytext to convert to Python
	local cmd = string.format("%s -m jupytext --to py:percent --output - '%s' 2>/dev/null", python_path, filepath)

	local output = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		return nil, "Failed to convert notebook"
	end

	return output, nil
end

-- Open notebook in readable format
function M.open_notebook(filepath)
	if not M.ensure_jupytext() then
		notifications.notify(
			"Install jupytext to view notebooks: pip install jupytext",
			vim.log.levels.WARN,
			{ action_required = true }
		)
		return false
	end

	-- Convert to markdown for viewing
	notifications.progress_start("notebook_convert", "Opening Notebook", "Converting to readable format...")

	local content, err = M.notebook_to_markdown(filepath)

	notifications.progress_finish("notebook_convert")

	if not content then
		notifications.notify_error("Failed to open notebook: " .. (err or "unknown error"))
		return false
	end

	-- Create a new buffer with the markdown content
	vim.cmd("enew")
	local buf = vim.api.nvim_get_current_buf()

	-- Set buffer options
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

	-- Set buffer name to indicate it's a view
	vim.api.nvim_buf_set_name(buf, filepath .. " [Notebook View]")

	-- Set the content
	local lines = vim.split(content, "\n")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Make it read-only
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	return true
end

-- Sync notebook with Python file
function M.sync_notebook_to_python(notebook_path, python_path)
	local python_cmd = M.get_python_for_jupytext()
	if not python_cmd then
		return false, "Python not found"
	end

	if not M.is_jupytext_installed() then
		return false, "Jupytext not installed"
	end

	local cmd =
		string.format("%s -m jupytext --to py:percent --output '%s' '%s'", python_cmd, python_path, notebook_path)

	vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		return false, "Failed to sync notebook"
	end

	return true, nil
end

-- Sync Python file with notebook
function M.sync_python_to_notebook(python_path, notebook_path)
	local python_cmd = M.get_python_for_jupytext()
	if not python_cmd then
		return false, "Python not found"
	end

	if not M.is_jupytext_installed() then
		return false, "Jupytext not installed"
	end

	local cmd = string.format("%s -m jupytext --to notebook --output '%s' '%s'", python_cmd, notebook_path, python_path)

	vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		return false, "Failed to sync Python file"
	end

	return true, nil
end

-- Set up auto-sync for paired files
function M.setup_pairing(filepath)
	local ext = vim.fn.fnamemodify(filepath, ":e")
	local base = vim.fn.fnamemodify(filepath, ":r")

	local pair_file
	if ext == "ipynb" then
		pair_file = base .. ".py"
	elseif ext == "py" then
		pair_file = base .. ".ipynb"
	else
		return
	end

	-- Check if pair file exists
	if vim.fn.filereadable(pair_file) == 0 then
		return
	end

	-- Set up auto-sync on save
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = filepath,
		callback = function()
			if ext == "ipynb" then
				M.sync_notebook_to_python(filepath, pair_file)
			else
				M.sync_python_to_notebook(filepath, pair_file)
			end
		end,
		group = vim.api.nvim_create_augroup("JupytextSync_" .. filepath, { clear = true }),
	})
end

return M
