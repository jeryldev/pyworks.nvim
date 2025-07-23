local M = {}
local config = require("pyworks.config")

-- Cache for expensive operations
local cache = {
	cwd = nil,
	venv_path = nil,
	last_cwd_check = nil,
}

-- Better select implementation (single source of truth)
function M.better_select(prompt, items, callback)
	if vim.ui then
		vim.ui.select(items, { prompt = prompt }, callback)
	else
		print(prompt .. ":")
		for i, item in ipairs(items) do
			print(i .. ": " .. item)
		end
		local choice = tonumber(vim.fn.input("Select (enter number): "))
		if choice and choice > 0 and choice <= #items then
			callback(items[choice])
		else
			callback(nil)
		end
	end
end

-- Get cached project paths
function M.get_project_paths()
	local current_cwd = vim.fn.getcwd()

	-- Cache for 5 seconds to avoid repeated calls
	local now = vim.loop.hrtime()
	if cache.cwd == current_cwd and cache.last_cwd_check and (now - cache.last_cwd_check) < 5e9 then
		return cache.cwd, cache.venv_path
	end

	cache.cwd = current_cwd
	cache.venv_path = current_cwd .. "/.venv"
	cache.last_cwd_check = now

	return cache.cwd, cache.venv_path
end

-- Async system call wrapper
function M.async_system_call(cmd, callback, options)
	options = options or {}
	local stdout_data = {}
	local stderr_data = {}

	local job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if data then
				vim.list_extend(stdout_data, data)
			end
		end,
		on_stderr = function(_, data)
			if data then
				vim.list_extend(stderr_data, data)
			end
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				local stdout = table.concat(stdout_data, "\n")
				local stderr = table.concat(stderr_data, "\n")
				callback(exit_code == 0, stdout, stderr, exit_code)
			end)
		end,
		cwd = options.cwd,
		env = options.env,
	})

	if job_id <= 0 then
		vim.schedule(function()
			callback(false, "", "Failed to start job", -1)
		end)
	end

	return job_id
end

-- Safe file write with proper error handling
function M.safe_file_write(filepath, content)
	local file, err = io.open(filepath, "w")
	if not file then
		return false, "Failed to open file: " .. (err or "unknown error")
	end

	local success, write_err = pcall(function()
		file:write(content)
		file:close()
	end)

	if not success then
		-- Try to close file if write failed
		pcall(function()
			file:close()
		end)
		return false, "Failed to write file: " .. (write_err or "unknown error")
	end

	return true
end

-- Safe file read with proper error handling
function M.safe_file_read(filepath)
	local file, err = io.open(filepath, "r")
	if not file then
		return nil, "Failed to open file: " .. (err or "unknown error")
	end

	local success, content_or_err = pcall(function()
		local content = file:read("*all")
		file:close()
		return content
	end)

	if not success then
		-- Try to close file if read failed
		pcall(function()
			file:close()
		end)
		return nil, "Failed to read file: " .. (content_or_err or "unknown error")
	end

	return content_or_err
end

-- Check if command exists
function M.command_exists(cmd)
	local handle = io.popen("command -v " .. cmd .. " 2>/dev/null")
	if handle then
		local result = handle:read("*a")
		handle:close()
		return result ~= ""
	end
	return false
end

-- Progress indicator for long operations
function M.progress_start(title)
	local progress_id = tostring(vim.loop.hrtime())
	config.state.progress[progress_id] = {
		title = title,
		start_time = vim.loop.hrtime(),
	}

	M.notify(title .. "...", vim.log.levels.INFO)
	return progress_id
end

function M.progress_end(progress_id, success, message)
	local progress_info = config.state.progress[progress_id]
	if progress_info then
		local elapsed = (vim.loop.hrtime() - progress_info.start_time) / 1e9
		local status = success and "completed" or "failed"
		local level = success and vim.log.levels.INFO or vim.log.levels.ERROR
		local icon = success and "success" or "error"

		M.notify(
			string.format("%s %s in %.2fs%s", progress_info.title, status, elapsed, message and (": " .. message) or ""),
			level,
			nil,
			icon
		)

		config.state.progress[progress_id] = nil
	end
end

-- Notification wrapper with consistent formatting
function M.notify(message, level, title, icon_name)
	level = level or vim.log.levels.INFO
	local icon = icon_name and config.icon(icon_name) or config.icon("python")
	local prefix = title and (icon .. " " .. title .. ": ") or (icon .. " ")
	vim.notify(prefix .. message, level)
end

-- Path manipulation utilities
function M.path_join(...)
	local parts = { ... }
	return table.concat(parts, "/")
end

function M.path_exists(path)
	local stat = vim.loop.fs_stat(path)
	return stat ~= nil
end

function M.ensure_directory(path)
	if not M.path_exists(path) then
		local success = vim.fn.mkdir(path, "p")
		return success == 1
	end
	return true
end

return M
