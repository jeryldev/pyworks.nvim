-- Jupytext integration for notebook viewing
-- Converts .ipynb JSON to readable format

local M = {}

local cache = require("pyworks.core.cache")
local notifications = require("pyworks.core.notifications")
local state = require("pyworks.core.state")
local utils = require("pyworks.utils")

-- Check if jupytext CLI is available (jupytext.nvim uses the CLI, not Python import)
-- filepath: optional, used to check the file's project venv
function M.is_jupytext_installed(filepath)
	-- First check if jupytext CLI is in PATH (this is what jupytext.nvim uses)
	if vim.fn.executable("jupytext") == 1 then
		return true
	end

	-- Check project venv for jupytext binary (using filepath if provided)
	local _, venv_path = utils.get_project_paths(filepath)
	if vim.fn.isdirectory(venv_path) == 1 then
		local venv_jupytext = venv_path .. "/bin/jupytext"
		if vim.fn.executable(venv_jupytext) == 1 then
			return true
		end
	end

	-- Fallback: check if Python can import jupytext (less reliable for CLI usage)
	local python_path = M.get_python_for_jupytext(filepath)
	if python_path then
		local ok, result = pcall(function()
			return vim.system({ python_path, "-c", "import jupytext" }, { text = true }):wait()
		end)
		if ok and result and result.code == 0 then
			return true
		end
	end

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
	if python_path:match(venv_path) then
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
				cache.invalidate("jupytext_check")
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
	if M.is_jupytext_installed() then
		return true -- Already installed, nothing to do
	end

	-- Don't auto-install, just return false so proper warnings are shown
	return false
end

-- Check if jupytext CLI is available in PATH or common venv locations
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
			-- Add directory to PATH (guard against nil PATH)
			local dir = vim.fn.fnamemodify(path, ":h")
			local current_path = vim.env.PATH or ""
			vim.env.PATH = dir .. ":" .. current_path
			return path
		end
	end

	return nil
end

-- Setup fallback handler for .ipynb files when jupytext CLI is not available
-- Shows notebooks as read-only JSON with helpful messages guiding users to install jupytext
function M.setup_fallback_handler()
	-- Clear jupytext.nvim's autocmds to prevent errors
	pcall(vim.api.nvim_clear_autocmds, {
		group = "jupytext.nvim",
		pattern = "*.ipynb",
	})

	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = vim.api.nvim_create_augroup("PyworksNotebookFallback", { clear = true }),
		pattern = "*.ipynb",
		callback = function(ev)
			-- Prevent other handlers from running
			pcall(vim.api.nvim_buf_set_var, ev.buf, "jupytext_handled", true)

			-- Get the filepath
			local filepath = vim.api.nvim_buf_get_name(ev.buf)
			if filepath == "" then
				filepath = ev.match or ev.file
			end

			-- Make absolute if needed
			if not filepath:match("^/") then
				local cwd = vim.fn.getcwd()
				if cwd and cwd ~= "" then
					filepath = cwd .. "/" .. filepath
				else
					filepath = vim.fn.expand(filepath)
				end
			end

			-- Safely load the file
			local ok, content = pcall(vim.fn.readfile, filepath)
			if not ok then
				vim.api.nvim_buf_set_lines(ev.buf, 0, -1, false, {
					"Error: Could not read notebook file",
					"",
					"File: " .. filepath,
					"",
					"Possible reasons:",
					"- File does not exist",
					"- Permission denied",
					"- Invalid path",
				})
				vim.bo[ev.buf].filetype = "text"
				vim.bo[ev.buf].modifiable = false

				vim.schedule(function()
					notifications.notify("Could not read notebook file", vim.log.levels.ERROR)
					notifications.notify("Check the file path and permissions", vim.log.levels.INFO)
				end)
			else
				-- Successfully read file, show as JSON
				vim.api.nvim_buf_set_lines(ev.buf, 0, -1, false, content)
				vim.bo[ev.buf].filetype = "json"
				vim.bo[ev.buf].modifiable = false

				vim.schedule(function()
					notifications.notify(
						"Notebook opened in JSON view (jupytext CLI not installed)",
						vim.log.levels.WARN
					)
					notifications.notify("Run :PyworksSetup from any .py file to install jupytext", vim.log.levels.INFO)
				end)
			end

			-- Mark as loaded to prevent re-processing
			pcall(vim.api.nvim_buf_set_var, ev.buf, "pyworks_notebook_loaded", true)
			vim.cmd.setlocal("buftype=nofile")
		end,
	})
end

-- Configure jupytext.nvim with optimal settings
-- Returns true if configured successfully, false if fallback is needed
function M.configure_jupytext_nvim()
	local jupytext_cmd = M.find_jupytext_cli()

	if not jupytext_cmd then
		-- No jupytext CLI available, setup fallback
		M.setup_fallback_handler()
		return false
	end

	-- jupytext CLI is available, clear fallback handler if it was set up
	pcall(vim.api.nvim_clear_autocmds, {
		group = "PyworksNotebookFallback",
	})

	-- Also clear jupytext.nvim's autocmds to force re-registration
	pcall(vim.api.nvim_clear_autocmds, {
		group = "jupytext.nvim",
	})

	-- Configure jupytext.nvim
	local ok, jupytext = pcall(require, "jupytext")
	if not ok then
		-- jupytext.nvim not installed, but CLI is available
		-- This shouldn't happen if dependencies are correct
		return false
	end

	-- Reset jupytext.nvim's internal state to force fresh setup
	if jupytext.state then
		jupytext.state = nil
	end

	jupytext.setup({
		style = "percent",
		output_extension = "auto",
		force_ft = nil,
		jupytext_command = jupytext_cmd,
		custom_language_formatting = {
			python = { extension = "py", style = "percent", comment = "#" },
		},
	})

	return true
end

return M
