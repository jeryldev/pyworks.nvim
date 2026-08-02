local M = {}

-- Cache for project path lookups (simple internal cache)
local cache = {
	cwd = nil,
	project_dir = nil,
	venv_path = nil,
	last_cwd_check = nil,
}

-- Note: For general caching, use require("pyworks.core.cache") instead

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

		-- A directory is a perfectly good starting point; only an unreadable
		-- *file* path is unusable. Treating directories as unresolvable sent
		-- callers to cwd and made them answer about the wrong project entirely -
		-- :PyworksReport asked about "<project>/probe.py", a file that never
		-- exists, and so reported "no venv" for projects that had one.
		local start_dir
		if vim.fn.isdirectory(abs_filepath) == 1 then
			start_dir = abs_filepath
		elseif vim.fn.filereadable(abs_filepath) == 1 then
			start_dir = vim.fn.fnamemodify(abs_filepath, ":h")
		else
			return vim.fn.getcwd(), vim.fn.getcwd() .. "/.venv"
		end

		-- SMART LOGIC: Find the project root by walking up the directory tree
		project_dir = M.find_project_root(start_dir)
		-- nil means "not inside a project". Path resolution still needs an
		-- answer, and it must stay local to the file: falling back to cwd would
		-- resolve /tmp/scratch.py against whatever project the editor happens to
		-- be sitting in, and hand it that project's venv. Callers that need to
		-- *act* ask M.is_project() instead.
		if not project_dir then
			project_dir = start_dir
		end
	else
		-- When no file is specified, use current working directory
		project_dir = vim.fn.getcwd()
	end

	-- Use project_dir as cache key for consistent caching across files in same project
	local cache_key = project_dir

	-- Cache for 5 seconds to avoid repeated calls
	local now = vim.uv.hrtime()
	if cache.cwd == cache_key and cache.last_cwd_check and (now - cache.last_cwd_check) < 5e9 then
		return cache.project_dir, cache.venv_path, cache.ambient
	end

	cache.cwd = cache_key
	cache.project_dir = project_dir
	local local_venv = project_dir .. "/.venv"
	cache.venv_path = local_venv
	cache.ambient = false

	-- A project without its own .venv falls back to whatever environment the
	-- shell had active. That is useful for reading, but installing into someone's
	-- conda base without saying so is not: the third return value lets callers
	-- warn or refuse.
	if vim.fn.isdirectory(local_venv) ~= 1 then
		if vim.env.VIRTUAL_ENV and vim.fn.isdirectory(vim.env.VIRTUAL_ENV) == 1 then
			cache.venv_path = vim.env.VIRTUAL_ENV
			cache.ambient = true
		elseif vim.env.CONDA_PREFIX and vim.fn.isdirectory(vim.env.CONDA_PREFIX) == 1 then
			cache.venv_path = vim.env.CONDA_PREFIX
			cache.ambient = true
		end
	end
	cache.last_cwd_check = now

	return project_dir, cache.venv_path, cache.ambient
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

-- Find the project root for a directory, or nil if this is not a project
--
-- Only strong markers establish a project. manage.py, app.py and main.py used
-- to qualify, but they are common enough to appear in any scratch directory,
-- and a match there means pyworks creates a venv beside the file.
--
-- This used to fall back to start_dir, so it never returned nil: every "only
-- act inside a project" guard was therefore always true, and pyworks would set
-- up a full environment (including a ~300MB venv) beside any stray .py file,
-- including one sitting in $HOME.
local STRONG_MARKERS = {
	".venv",
	"pyproject.toml",
	".git",
	"setup.py",
	"setup.cfg",
	"requirements.txt",
	"Pipfile",
	"poetry.lock",
	"uv.lock",
	"conda.yaml",
	"environment.yml",
	"dvc.yaml",
	"mlflow.yaml",
	"tox.ini",
	".dvcignore",
}

local function has_marker(dir, markers)
	for _, marker in ipairs(markers) do
		local path = dir .. "/" .. marker
		if vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1 then
			return true
		end
	end
	return false
end

function M.find_project_root(start_dir)
	if not start_dir or start_dir == "" then
		return nil
	end

	local home = vim.fn.fnamemodify(vim.env.HOME or "", ":p"):gsub("/$", "")
	local current = vim.fn.fnamemodify(start_dir, ":p"):gsub("/$", "")
	local last = ""

	while current ~= last and current ~= "" do
		-- $HOME is never a project: a stray main.py there would otherwise put a
		-- venv in the user's home directory
		if current ~= home then
			if has_marker(current, STRONG_MARKERS) then
				return current
			end
		end

		last = current
		current = vim.fn.fnamemodify(current, ":h")
	end

	return nil
end

-- Is this file inside a real project? This is the question every "only act in a
-- project" guard was asking while find_project_root could never answer no.
function M.is_project(filepath)
	local dir = (filepath and filepath ~= "") and vim.fn.fnamemodify(filepath, ":p:h") or vim.fn.getcwd()
	return M.find_project_root(dir) ~= nil
end

-- Default timeout for system commands (in milliseconds)
local DEFAULT_TIMEOUT_MS = 30000 -- 30 seconds

-- Async system call wrapper using vim.system() (Neovim 0.10+)
-- Returns: SystemObj that can be used to kill the process
function M.async_system_call(cmd, callback, options)
	vim.validate({
		cmd = { cmd, "table" },
		callback = { callback, "function" },
		options = { options, "table", true },
	})
	options = options or {}
	local timeout_ms = options.timeout or DEFAULT_TIMEOUT_MS

	local system_opts = {
		text = true,
		cwd = options.cwd,
		env = options.env,
		timeout = timeout_ms > 0 and timeout_ms or nil,
	}

	local ok, result = pcall(vim.system, cmd, system_opts, function(obj)
		vim.schedule(function()
			local success = obj.code == 0
			local stdout = obj.stdout or ""
			local stderr = obj.stderr or ""
			local exit_code = obj.code

			if obj.signal == 15 or obj.signal == 9 then
				callback(false, "", "Command timed out after " .. (timeout_ms / 1000) .. " seconds", -2)
			else
				callback(success, stdout, stderr, exit_code)
			end
		end)
	end)

	if not ok then
		vim.schedule(function()
			callback(false, "", "Failed to start job: " .. tostring(result), -1)
		end)
		return nil
	end

	return result
end

-- Synchronous system call with timeout using vim.system() (Neovim 0.10+)
-- Returns: success (boolean), output (string), exit_code (number)
function M.system_with_timeout(cmd, timeout_ms)
	vim.validate({
		cmd = { cmd, "table" },
		timeout_ms = { timeout_ms, "number", true },
	})
	timeout_ms = timeout_ms or DEFAULT_TIMEOUT_MS

	local ok, sys_obj = pcall(vim.system, cmd, {
		text = true,
		timeout = timeout_ms > 0 and timeout_ms or nil,
	})

	if not ok then
		return false, "Failed to start command: " .. tostring(sys_obj), -1
	end

	local result = sys_obj:wait()

	if result.signal == 15 or result.signal == 9 then
		return false, "Command timed out", -2
	end

	local success = result.code == 0
	local stdout = result.stdout or ""

	return success, stdout, result.code
end

-- Safe file write with proper error handling
-- Write a file atomically: temp file, then rename into place
--
-- Opening the target directly truncates it before a single byte is written, so
-- an interrupted or failed write destroys whatever was there. That matters most
-- for notebooks, where the file *is* the user's work.
--
-- close() is checked, not just write(): in LuaJIT file:write returns the handle
-- (always truthy) and buffered data is only flushed at close, so a full disk
-- surfaces there and nowhere else.
function M.safe_file_write(filepath, content)
	local temp = filepath .. ".pyworks.tmp"

	local file, err = io.open(temp, "w")
	if not file then
		return false, "Failed to open temporary file: " .. (err or "unknown error")
	end

	local success, write_err = pcall(function()
		assert(file:write(content))
		assert(file:close())
	end)

	if not success then
		pcall(function()
			file:close()
		end)
		pcall(os.remove, temp)
		return false, "Failed to write file: " .. tostring(write_err)
	end

	-- Keep the original's permissions; rename would otherwise apply the umask
	local mode = vim.fn.getfperm(filepath)
	if mode ~= "" then
		pcall(vim.fn.setfperm, temp, mode)
	end

	local renamed, rename_err = os.rename(temp, filepath)
	if not renamed then
		pcall(os.remove, temp)
		return false, "Failed to replace file: " .. tostring(rename_err)
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

-- Check if a Neovim plugin is installed (lazy.nvim compatible)
function M.is_plugin_installed(plugin_name)
	local lazy_ok, lazy = pcall(require, "lazy.core.config")
	if lazy_ok and lazy.plugins and lazy.plugins[plugin_name] then
		return true
	end
	return false
end

-- Check if a Python module can be imported
function M.check_python_import(module_name)
	if not module_name or not module_name:match("^[%w_%.]+$") then
		return false
	end
	local python_cmd = vim.g.python3_host_prog or "python3"
	local ok, result = pcall(function()
		return vim.system({ python_cmd, "-c", "import " .. module_name }, { text = true }):wait()
	end)
	return ok and result and result.code == 0
end

-- Set a buffer-local variable, tolerating a buffer that no longer exists
--
-- Buffer variables are frequently written from deferred callbacks (kernel
-- startup, notebook conversion), by which point the user may have closed the
-- file or jupytext may have replaced the buffer. vim.b[<invalid>] raises
-- "scoped variable: Invalid buffer id" from inside a vim.schedule callback,
-- where no caller is left to catch it.
-- Returns true if the value was set.
function M.safe_buf_set_var(bufnr, name, value)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local ok = pcall(function()
		vim.b[bufnr][name] = value
	end)
	return ok
end

return M
