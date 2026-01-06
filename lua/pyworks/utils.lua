local M = {}

-- Cache for expensive operations
local cache = {
	cwd = nil,
	project_dir = nil, -- The actual project directory
	venv_path = nil,
	last_cwd_check = nil,
}

-- Generic data cache for expensive operations
local data_cache = {}

-- Get cached data or fetch it
function M.get_cached(key, fetcher, ttl)
	ttl = ttl or 5000 -- Default 5 second TTL
	local now = vim.uv.hrtime() / 1e6
	local entry = data_cache[key]

	if entry and entry.result and (now - entry.timestamp) < ttl then
		return entry.result
	end

	local result = fetcher()
	data_cache[key] = {
		result = result,
		timestamp = now,
	}
	return result
end

-- Clear cache entry
function M.clear_cache(key)
	if key then
		data_cache[key] = nil
	else
		data_cache = {}
	end
end

-- Check if virtual environment exists
function M.has_venv()
	local _, venv_path = M.get_project_paths()
	return vim.fn.isdirectory(venv_path) == 1
end

-- Get Python executable path from venv
function M.get_python_path()
	local _, venv_path = M.get_project_paths()
	local python_path = venv_path .. "/bin/python3"

	-- Try python3 first, then python
	if vim.fn.executable(python_path) ~= 1 then
		python_path = venv_path .. "/bin/python"
		if vim.fn.executable(python_path) ~= 1 then
			return nil
		end
	end

	return python_path
end

-- Check if venv is properly configured
function M.is_venv_configured()
	local python_path = M.get_python_path()
	return python_path and vim.g.python3_host_prog == python_path
end

-- Ensure venv is in PATH
function M.ensure_venv_in_path()
	local _, venv_path = M.get_project_paths()
	local venv_bin = venv_path .. "/bin"

	-- Guard against nil PATH (unlikely but possible)
	local current_path = vim.env.PATH or ""
	if not current_path:match(vim.pesc(venv_bin)) then
		vim.env.PATH = venv_bin .. ":" .. current_path
		return true
	end
	return false
end

-- Detect package manager (uv vs pip)
function M.detect_package_manager()
	local _, venv_path = M.get_project_paths()

	-- Check for uv in venv first
	local venv_uv = venv_path .. "/bin/uv"
	if vim.fn.executable(venv_uv) == 1 then
		return "uv", venv_uv
	end

	-- Check for system uv
	if vim.fn.executable("uv") == 1 then
		return "uv", "uv"
	end

	-- Fall back to pip
	local venv_pip = venv_path .. "/bin/pip"
	if vim.fn.executable(venv_pip) == 1 then
		return "pip", venv_pip
	end

	return "pip", "pip"
end

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
-- Now accepts optional filepath to detect project from file location
function M.get_project_paths(filepath)
	local project_dir

	if filepath and filepath ~= "" then
		-- Ensure we have an absolute path
		local abs_filepath = filepath

		-- Check if it's already absolute
		if not filepath:match("^/") and not filepath:match("^~") then
			-- It's relative, make it absolute
			abs_filepath = vim.fn.fnamemodify(filepath, ":p")
		end

		-- Validate the path exists
		if vim.fn.filereadable(abs_filepath) ~= 1 then
			-- If file doesn't exist, use cwd as base
			return vim.fn.getcwd(), vim.fn.getcwd() .. "/.venv"
		end

		-- SMART LOGIC: Find the project root by walking up the directory tree
		project_dir = M.find_project_root(vim.fn.fnamemodify(abs_filepath, ":h"))
	else
		-- When no file is specified, use current working directory
		project_dir = vim.fn.getcwd()
	end

	-- Use project_dir as cache key for consistent caching across files in same project
	local cache_key = project_dir

	-- Cache for 5 seconds to avoid repeated calls
	local now = vim.uv.hrtime()
	if cache.cwd == cache_key and cache.last_cwd_check and (now - cache.last_cwd_check) < 5e9 then
		return cache.project_dir, cache.venv_path
	end

	cache.cwd = cache_key
	cache.project_dir = project_dir
	cache.venv_path = project_dir .. "/.venv"
	cache.last_cwd_check = now

	return project_dir, cache.venv_path
end

-- Detect project type based on files present
function M.detect_project_type(project_dir)
	if vim.fn.filereadable(project_dir .. "/manage.py") == 1 then
		return "Django"
	elseif vim.fn.filereadable(project_dir .. "/app.py") == 1 then
		-- Could be Flask or Streamlit
		local content = vim.fn.readfile(project_dir .. "/app.py", "", 100) -- Read first 100 lines
		local content_str = table.concat(content, "\n")
		if content_str:match("Flask") then
			return "Flask"
		elseif content_str:match("streamlit") or content_str:match("st%.") then
			return "Streamlit"
		else
			return "Python App"
		end
	elseif vim.fn.filereadable(project_dir .. "/main.py") == 1 then
		local content = vim.fn.readfile(project_dir .. "/main.py", "", 100)
		local content_str = table.concat(content, "\n")
		if content_str:match("FastAPI") or content_str:match("fastapi") then
			return "FastAPI"
		else
			return "Python"
		end
	elseif vim.fn.filereadable(project_dir .. "/dvc.yaml") == 1 then
		return "DVC/MLOps"
	elseif vim.fn.filereadable(project_dir .. "/mlflow.yaml") == 1 then
		return "MLflow"
	elseif vim.fn.filereadable(project_dir .. "/pyproject.toml") == 1 then
		return "Poetry/Modern Python"
	elseif vim.fn.filereadable(project_dir .. "/setup.py") == 1 then
		return "Python Package"
	elseif vim.fn.filereadable(project_dir .. "/requirements.txt") == 1 then
		return "Python Project"
	elseif
		vim.fn.filereadable(project_dir .. "/environment.yml") == 1
		or vim.fn.filereadable(project_dir .. "/conda.yaml") == 1
	then
		return "Conda Project"
	else
		return "Python"
	end
end

-- Find project root by looking for markers
function M.find_project_root(start_dir)
	local markers = {
		".venv", -- Virtual environment (highest priority)
		"pyproject.toml", -- Modern Python project
		"setup.py", -- Python package
		"requirements.txt", -- Python requirements
		"manage.py", -- Django project
		"app.py", -- Flask/Streamlit app
		"main.py", -- FastAPI/general entry point
		"Pipfile", -- Pipenv project
		"poetry.lock", -- Poetry project
		"conda.yaml", -- Conda environment
		"environment.yml", -- Conda/Mamba env
		"dvc.yaml", -- DVC (ML pipelines)
		"mlflow.yaml", -- MLflow project
		"setup.cfg", -- Python package config
		"tox.ini", -- Testing config (often at root)
		".dvcignore", -- DVC project
		"uv.lock", -- UV lock file
		".git", -- Git repository (lower priority)
	}

	local current = start_dir
	local last = ""

	-- Walk up the directory tree
	while current ~= last do
		-- Check for markers
		for _, marker in ipairs(markers) do
			local marker_path = current .. "/" .. marker
			if vim.fn.isdirectory(marker_path) == 1 or vim.fn.filereadable(marker_path) == 1 then
				return current
			end
		end

		last = current
		current = vim.fn.fnamemodify(current, ":h")
	end

	-- If no project root found, check if file is under Neovim's working directory
	local cwd = vim.fn.getcwd()

	if cwd and cwd ~= "" then
		-- Check if the file is under the current working directory
		local relative_path = vim.fn.fnamemodify(start_dir, ":p")
		local cwd_absolute = vim.fn.fnamemodify(cwd, ":p")

		-- If the file is under cwd, use cwd as project root
		if relative_path:sub(1, #cwd_absolute) == cwd_absolute then
			return cwd_absolute
		end
	end

	-- Last resort: use the file's directory
	return start_dir
end

-- Default timeout for system commands (in milliseconds)
local DEFAULT_TIMEOUT_MS = 30000 -- 30 seconds

-- Async system call wrapper with timeout support
function M.async_system_call(cmd, callback, options)
	vim.validate({
		cmd = { cmd, { "string", "table" } },
		callback = { callback, "function" },
		options = { options, "table", true },
	})
	options = options or {}
	local stdout_data = {}
	local stderr_data = {}
	local timeout_ms = options.timeout or DEFAULT_TIMEOUT_MS
	local timer = nil
	local job_completed = false

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
			job_completed = true
			if timer then
				timer:stop()
				timer:close()
				timer = nil
			end
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
		return job_id
	end

	-- Set up timeout timer
	if timeout_ms > 0 then
		timer = vim.uv.new_timer()
		timer:start(
			timeout_ms,
			0,
			vim.schedule_wrap(function()
				if not job_completed then
					pcall(vim.fn.jobstop, job_id)
					if timer then
						timer:stop()
						timer:close()
						timer = nil
					end
					callback(false, "", "Command timed out after " .. (timeout_ms / 1000) .. " seconds", -2)
				end
			end)
		)
	end

	return job_id
end

-- Synchronous system call with timeout (blocks but won't hang forever)
-- Returns: success (boolean), output (string), exit_code (number)
function M.system_with_timeout(cmd, timeout_ms)
	timeout_ms = timeout_ms or DEFAULT_TIMEOUT_MS
	local result = { success = false, output = "", exit_code = -1, timed_out = false }
	local done = false

	local job_id = M.async_system_call(cmd, function(success, stdout, stderr, exit_code)
		result.success = success
		result.output = stdout
		result.stderr = stderr
		result.exit_code = exit_code
		result.timed_out = exit_code == -2
		done = true
	end, { timeout = timeout_ms })

	if job_id <= 0 then
		return false, "Failed to start command", -1
	end

	-- Wait for completion (with vim.wait to allow UI updates)
	local wait_result = vim.wait(timeout_ms + 1000, function()
		return done
	end, 10)

	if not wait_result then
		pcall(vim.fn.jobstop, job_id)
		return false, "Command timed out", -2
	end

	return result.success, result.output, result.exit_code
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
	-- Use vim.fn.executable for safety instead of shell command
	if vim.fn.executable(cmd) == 1 then
		return true
	end
	return false
end

-- Safe vim.schedule wrapper with error handling
-- Prevents silent failures in async operations
function M.safe_schedule(fn, error_context)
	vim.validate({
		fn = { fn, "function" },
		error_context = { error_context, "string", true },
	})
	vim.schedule(function()
		local ok, err = pcall(fn)
		if not ok then
			-- Log the error (don't use notifications module to avoid circular dependency)
			vim.api.nvim_err_writeln(
				string.format(
					"[Pyworks] Async error%s: %s",
					error_context and (" in " .. error_context) or "",
					tostring(err)
				)
			)
		end
	end)
end

-- Path manipulation utilities
function M.path_join(...)
	local parts = { ... }
	return table.concat(parts, "/")
end

function M.path_exists(path)
	local stat = vim.uv.fs_stat(path)
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
