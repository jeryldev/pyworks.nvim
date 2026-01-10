-- Jupytext integration for notebook viewing
-- Handles .ipynb files directly using jupytext CLI (no jupytext.nvim dependency)

local M = {}

local cache = require("pyworks.core.cache")
local notifications = require("pyworks.core.notifications")
local state = require("pyworks.core.state")
local utils = require("pyworks.utils")

-- Augroup for notebook handling
local augroup = vim.api.nvim_create_augroup("PyworksNotebook", { clear = true })

-- Track buffers we're currently processing to prevent recursion
local processing_buffers = {}

-- Check if jupytext CLI is available
-- filepath: optional, used to check the file's project venv
function M.is_jupytext_installed(filepath)
	-- Check cache first
	local cache_key = "jupytext_installed"
	local cached = cache.get(cache_key)
	if cached ~= nil then
		return cached
	end

	-- Check if jupytext CLI is in PATH
	if vim.fn.executable("jupytext") == 1 then
		cache.set(cache_key, true, 300000) -- Cache for 5 minutes
		return true
	end

	-- Check project venv for jupytext binary (using filepath if provided)
	local _, venv_path = utils.get_project_paths(filepath)
	if vim.fn.isdirectory(venv_path) == 1 then
		local venv_jupytext = venv_path .. "/bin/jupytext"
		if vim.fn.executable(venv_jupytext) == 1 then
			cache.set(cache_key, true, 300000)
			return true
		end
	end

	-- Fallback: check if Python can import jupytext
	local python_path = M.get_python_for_jupytext(filepath)
	if python_path then
		local ok, result = pcall(function()
			return vim.system({ python_path, "-c", "import jupytext" }, { text = true }):wait()
		end)
		if ok and result and result.code == 0 then
			cache.set(cache_key, true, 300000)
			return true
		end
	end

	cache.set(cache_key, false, 60000) -- Cache negative result for 1 minute
	return false
end

-- Get Python interpreter for jupytext
function M.get_python_for_jupytext(filepath)
	-- Get project-specific paths
	local _, venv_path = utils.get_project_paths(filepath)

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
	local _, venv_path = utils.get_project_paths(filepath)
	local pip_cmd
	if venv_path and python_path:match(vim.pesc(venv_path)) then
		pip_cmd = venv_path .. "/bin/pip"
	else
		pip_cmd = python_path .. " -m pip"
	end

	local cmd = string.format("%s install jupytext", pip_cmd)

	-- vim.system requires a table; wrap string commands in shell invocation
	local cmd_table = { "sh", "-c", cmd }

	-- Use vim.system for modern Neovim 0.10+
	local ok, _ = pcall(vim.system, cmd_table, { text = true }, function(obj)
		vim.schedule(function()
			if obj.code == 0 then
				cache.invalidate("jupytext_installed")
				notifications.progress_finish("jupytext_install", "Jupytext installed successfully")
				state.set(state.KEYS.PERSISTENT_JUPYTEXT, true)
			else
				notifications.progress_finish("jupytext_install")
				notifications.notify_error("Failed to install jupytext")
			end
		end)
	end)

	if not ok then
		notifications.progress_finish("jupytext_install")
		notifications.notify_error("Failed to start jupytext installation")
		return false
	end

	return true
end

-- Ensure jupytext is available
function M.ensure_jupytext(filepath)
	return M.is_jupytext_installed(filepath)
end

-- Find jupytext CLI in PATH or common venv locations
function M.find_jupytext_cli(filepath)
	-- Check if already in PATH
	if vim.fn.executable("jupytext") == 1 then
		return "jupytext"
	end

	-- Build list of paths to check
	local venv_paths = {}

	-- First priority: project venv based on the file being opened
	if filepath and filepath ~= "" then
		local _, venv_path = utils.get_project_paths(filepath)
		if venv_path then
			table.insert(venv_paths, venv_path .. "/bin/jupytext")
		end
	end

	-- Second: cwd-based venv
	table.insert(venv_paths, vim.fn.getcwd() .. "/.venv/bin/jupytext")
	-- Third: user local bin
	table.insert(venv_paths, vim.fn.expand("~") .. "/.local/bin/jupytext")
	-- Fourth: parent directory venv
	table.insert(venv_paths, vim.fn.fnamemodify(vim.fn.getcwd(), ":h") .. "/.venv/bin/jupytext")

	for _, path in ipairs(venv_paths) do
		if vim.fn.executable(path) == 1 then
			-- Add directory to PATH if not already present (prevents accumulation)
			local dir = vim.fn.fnamemodify(path, ":h")
			local current_path = vim.env.PATH or ""
			local path_pattern = vim.pesc(dir) .. "[:\n]?"
			if not current_path:match("^" .. path_pattern) and not current_path:match(":" .. path_pattern) then
				vim.env.PATH = dir .. ":" .. current_path
			end
			return path
		end
	end

	return nil
end

-- Convert .ipynb to percent-format Python script using jupytext CLI
local function convert_ipynb_to_percent(filepath)
	local jupytext_cmd = M.find_jupytext_cli(filepath)
	if not jupytext_cmd then
		return nil, "jupytext CLI not found"
	end

	local result = vim.system({
		jupytext_cmd,
		"--to",
		"py:percent",
		"--output",
		"-",
		filepath,
	}, { text = true }):wait()

	if result.code ~= 0 then
		return nil, result.stderr or "jupytext conversion failed"
	end

	return result.stdout, nil
end

-- Convert percent-format Python script back to .ipynb using jupytext CLI
local function convert_percent_to_ipynb(content, filepath)
	local jupytext_cmd = M.find_jupytext_cli(filepath)
	if not jupytext_cmd then
		return nil, "jupytext CLI not found"
	end

	local result = vim.system({
		jupytext_cmd,
		"--to",
		"ipynb",
		"--output",
		"-",
		"-",
	}, { text = true, stdin = content }):wait()

	if result.code ~= 0 then
		return nil, result.stderr or "jupytext conversion failed"
	end

	return result.stdout, nil
end

-- Read notebook and convert to percent format
local function read_notebook(bufnr, filepath)
	-- Mark as processing to prevent recursion
	processing_buffers[bufnr] = true

	-- Disable swap file for this buffer to prevent E325 errors
	vim.bo[bufnr].swapfile = false

	-- Try to convert using jupytext
	local content, err = convert_ipynb_to_percent(filepath)

	if content then
		-- Successfully converted - set buffer content
		local lines = vim.split(content, "\n", { plain = true })
		-- Remove trailing empty line if present
		if lines[#lines] == "" then
			table.remove(lines)
		end

		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		vim.bo[bufnr].filetype = "python"
		vim.bo[bufnr].modified = false

		-- Store original filepath for saving
		vim.b[bufnr].pyworks_notebook_path = filepath
		vim.b[bufnr].pyworks_notebook_loaded = true
	else
		-- Conversion failed - show JSON fallback with helpful message
		local ok, file_content = pcall(vim.fn.readfile, filepath)
		if ok then
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, file_content)
			vim.bo[bufnr].filetype = "json"
			vim.bo[bufnr].modifiable = false

			vim.schedule(function()
				notifications.notify("Notebook opened in JSON view (jupytext not available)", vim.log.levels.WARN)
				if err then
					notifications.notify("Error: " .. err, vim.log.levels.DEBUG)
				end
				notifications.notify("Run :PyworksSetup to install jupytext", vim.log.levels.INFO)
			end)
		else
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"Error: Could not read notebook file",
				"",
				"File: " .. filepath,
				"",
				"Run :PyworksSetup to configure Python environment",
			})
			vim.bo[bufnr].filetype = "text"
			vim.bo[bufnr].modifiable = false
		end
	end

	-- Clear processing flag
	processing_buffers[bufnr] = nil
end

-- Write notebook back to .ipynb format
local function write_notebook(bufnr, filepath)
	-- Get buffer content
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	-- Convert back to ipynb
	local ipynb_content, err = convert_percent_to_ipynb(content, filepath)

	if not ipynb_content then
		notifications.notify_error("Failed to save notebook: " .. (err or "unknown error"))
		return false
	end

	-- Write to file
	local file, open_err = io.open(filepath, "w")
	if not file then
		notifications.notify_error("Failed to write file: " .. (open_err or "unknown error"))
		return false
	end

	local write_ok, write_err = file:write(ipynb_content)
	file:close()

	if not write_ok then
		notifications.notify_error("Failed to write content: " .. (write_err or "unknown error"))
		return false
	end

	vim.bo[bufnr].modified = false
	notifications.notify("Notebook saved: " .. vim.fn.fnamemodify(filepath, ":t"), vim.log.levels.INFO)
	return true
end

-- Setup notebook handling autocmds
function M.setup_notebook_handler()
	-- Clear any existing autocmds in our group
	vim.api.nvim_clear_autocmds({ group = augroup })

	-- Clean up buffer-specific state on BufDelete to prevent memory leaks
	vim.api.nvim_create_autocmd("BufDelete", {
		group = augroup,
		callback = function(ev)
			processing_buffers[ev.buf] = nil
		end,
		desc = "Pyworks: Clean up notebook buffer state",
	})

	-- BufReadCmd: Intercept .ipynb file reads and convert to percent format
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = augroup,
		pattern = "*.ipynb",
		callback = function(ev)
			local bufnr = ev.buf
			local filepath = ev.match

			-- Skip if already processing this buffer
			if processing_buffers[bufnr] then
				return
			end

			-- Ensure absolute path
			if not filepath:match("^/") then
				filepath = vim.fn.fnamemodify(filepath, ":p")
			end

			-- Check if file exists
			if vim.fn.filereadable(filepath) ~= 1 then
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
					"Error: File not found",
					"",
					"File: " .. filepath,
				})
				vim.bo[bufnr].filetype = "text"
				vim.bo[bufnr].buftype = "nofile"
				return
			end

			read_notebook(bufnr, filepath)
		end,
		desc = "Pyworks: Read .ipynb files as percent-format Python",
	})

	-- BufWriteCmd: Intercept .ipynb file writes and convert back to JSON
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = augroup,
		pattern = "*.ipynb",
		callback = function(ev)
			local bufnr = ev.buf
			local filepath = vim.b[bufnr].pyworks_notebook_path or ev.match

			-- Ensure absolute path
			if not filepath:match("^/") then
				filepath = vim.fn.fnamemodify(filepath, ":p")
			end

			write_notebook(bufnr, filepath)
		end,
		desc = "Pyworks: Write .ipynb files from percent-format Python",
	})
end

-- Configure notebook handling (called from init.lua)
-- Returns true if configured successfully
function M.configure_notebook_handler()
	-- Check for jupytext.nvim plugin conflict
	local has_jupytext_nvim = pcall(require, "jupytext")
	if has_jupytext_nvim then
		notifications.notify(
			"jupytext.nvim detected! This may conflict with pyworks notebook handling.\n"
				.. "Either: (1) Remove jupytext.nvim from your config, OR\n"
				.. "(2) Set skip_jupytext = true in pyworks.setup()",
			vim.log.levels.WARN
		)
		-- Still set up our handler - user may want to migrate
	end

	-- Set up our notebook handler
	M.setup_notebook_handler()

	-- Check if jupytext CLI is available
	local jupytext_cmd = M.find_jupytext_cli()
	if jupytext_cmd then
		return true
	end

	-- jupytext not available, but handler is set up (will show fallback view)
	return false
end

-- Reload a notebook buffer (useful after installing jupytext)
function M.reload_notebook(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local filepath = vim.b[bufnr].pyworks_notebook_path or vim.api.nvim_buf_get_name(bufnr)

	if not filepath:match("%.ipynb$") then
		notifications.notify("Not a notebook file", vim.log.levels.WARN)
		return false
	end

	-- Clear cache to force re-check of jupytext availability
	cache.invalidate("jupytext_installed")

	-- Re-read the notebook
	vim.bo[bufnr].modifiable = true
	read_notebook(bufnr, filepath)
	return true
end

-- Legacy function name for compatibility
M.configure_jupytext_nvim = M.configure_notebook_handler

return M
