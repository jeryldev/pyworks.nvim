-- Error handling utilities for pyworks
local M = {}

-- Consistent error message prefix (no emoji for terminal compatibility)
local ERROR_PREFIX = "[Pyworks]"

-- Format error message consistently
local function format_error(message)
	return string.format("%s %s", ERROR_PREFIX, message)
end

-- Protected function execution with user-friendly error messages
function M.protected_call(func, error_prefix, ...)
	local ok, result = pcall(func, ...)
	if not ok then
		local error_msg = tostring(result)
		-- Clean up error message
		error_msg = error_msg:gsub("^[^:]+:%d+:%s*", "") -- Remove file:line: prefix
		error_msg = error_msg:gsub("^attempt to ", "") -- Remove "attempt to" prefix

		vim.notify(format_error(string.format("%s: %s", error_prefix or "Error", error_msg)), vim.log.levels.ERROR)
		return false, nil
	end
	return true, result
end

-- Validate file path
function M.validate_filepath(filepath, operation)
	operation = operation or "operation"

	if not filepath or filepath == "" then
		vim.notify(format_error(string.format("Cannot %s: No file path provided", operation)), vim.log.levels.ERROR)
		return nil
	end

	-- Make absolute if relative
	if not filepath:match("^/") then
		filepath = vim.fn.fnamemodify(filepath, ":p")
	end

	-- Check if file exists
	if vim.fn.filereadable(filepath) ~= 1 then
		vim.notify(
			format_error(string.format("Cannot %s: File not found: %s", operation, filepath)),
			vim.log.levels.ERROR
		)
		return nil
	end

	return filepath
end

-- Validate directory path
function M.validate_directory(dirpath, operation)
	operation = operation or "operation"

	if not dirpath or dirpath == "" then
		vim.notify(
			format_error(string.format("Cannot %s: No directory path provided", operation)),
			vim.log.levels.ERROR
		)
		return nil
	end

	-- Make absolute if relative
	if not dirpath:match("^/") then
		dirpath = vim.fn.fnamemodify(dirpath, ":p")
	end

	-- Check if directory exists
	if vim.fn.isdirectory(dirpath) ~= 1 then
		vim.notify(
			format_error(string.format("Cannot %s: Directory not found: %s", operation, dirpath)),
			vim.log.levels.ERROR
		)
		return nil
	end

	return dirpath
end

-- Validate executable
function M.validate_executable(exe_name, friendly_name)
	friendly_name = friendly_name or exe_name

	if vim.fn.executable(exe_name) ~= 1 then
		vim.notify(
			format_error(string.format("%s not found. Please install %s first.", friendly_name, friendly_name)),
			vim.log.levels.ERROR
		)
		return false
	end
	return true
end

-- Validate package list
function M.validate_packages(packages, language)
	language = language or "package"

	if not packages or type(packages) ~= "table" or #packages == 0 then
		vim.notify(format_error(string.format("No %s packages specified", language)), vim.log.levels.ERROR)
		return nil
	end

	-- Filter out empty strings
	local valid_packages = {}
	for _, pkg in ipairs(packages) do
		if pkg and pkg ~= "" then
			table.insert(valid_packages, pkg)
		end
	end

	if #valid_packages == 0 then
		vim.notify(format_error(string.format("No valid %s packages specified", language)), vim.log.levels.ERROR)
		return nil
	end

	return valid_packages
end

-- Handle async job errors
function M.handle_job_error(job_id, exit_code, cmd_description)
	if exit_code ~= 0 then
		vim.notify(
			format_error(string.format("%s failed with exit code %d", cmd_description or "Command", exit_code)),
			vim.log.levels.ERROR
		)
		return false
	end
	return true
end

-- Wrap a function with error handling
function M.wrap(func, error_prefix)
	return function(...)
		return M.protected_call(func, error_prefix, ...)
	end
end

-- Create error buffer with detailed information
function M.show_error_details(title, lines)
	-- Create a new buffer
	local buf = vim.api.nvim_create_buf(false, true)

	-- Set buffer options
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "markdown"

	-- Add title and content
	local content = { "# " .. title, "", "```" }
	vim.list_extend(content, lines)
	table.insert(content, "```")
	table.insert(content, "")
	table.insert(content, "Press 'q' to close this window")

	-- Set lines
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	vim.bo[buf].modifiable = false

	-- Open in a split
	vim.cmd("split")
	vim.api.nvim_win_set_buf(0, buf)

	-- Set up keybinding to close
	vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
end

return M
