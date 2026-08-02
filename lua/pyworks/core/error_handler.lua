-- Error handling utilities for pyworks
local M = {}

-- Consistent error message prefix (no emoji for terminal compatibility)
local ERROR_PREFIX = "[Pyworks]"

-- Format error message consistently
local function format_error(message)
	return string.format("%s %s", ERROR_PREFIX, message)
end

-- Protected function execution with user-friendly error messages
--
-- Returns (did_not_throw, result). The first value says only that the call did
-- not raise - a function returning false still yields true here. Callers that
-- care whether the *operation* succeeded must read the second value; treating
-- the first as success is what printed "Python environment ready" over a failed
-- setup.
--
-- Convention: use this module for user-facing validation and for calls whose
-- failure should be reported to the user. Everything else uses plain pcall.
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

-- Wrap a function with error handling
function M.wrap(func, error_prefix)
	return function(...)
		return M.protected_call(func, error_prefix, ...)
	end
end

return M
