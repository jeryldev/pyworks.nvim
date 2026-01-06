-- State management for pyworks.nvim
-- Manages plugin state and persists important data

local M = {}

-- In-memory state storage
local state = {}

-- Persistent state file path
local state_file = vim.fn.stdpath("data") .. "/pyworks_state.json"

-- Debounce timer for saves
local save_timer = nil
local SAVE_DEBOUNCE_MS = 500

-- Load state from disk
local function load_persistent_state()
	local file = io.open(state_file, "r")
	if not file then
		return {}
	end

	local content = file:read("*all")
	file:close()

	local ok, data = pcall(vim.json.decode, content)
	if ok then
		return data
	end

	return {}
end

-- Save state to disk atomically (write to temp file, then rename)
local function save_persistent_state()
	-- Filter only persistent keys
	local persistent = {}
	for key, value in pairs(state) do
		if key:match("^persistent_") or key:match("^initialized_") then
			persistent[key] = value
		end
	end

	-- Encode to JSON
	local ok, json_content = pcall(vim.json.encode, persistent)
	if not ok then
		return false
	end

	-- Write to temp file first (atomic write pattern)
	local temp_file = state_file .. ".tmp"
	local file = io.open(temp_file, "w")
	if not file then
		return false
	end

	local write_ok = pcall(function()
		file:write(json_content)
		file:flush()
		file:close()
	end)

	if not write_ok then
		pcall(os.remove, temp_file)
		return false
	end

	-- Rename temp file to actual file (atomic on most filesystems)
	local rename_ok = os.rename(temp_file, state_file)
	if not rename_ok then
		pcall(os.remove, temp_file)
		return false
	end

	return true
end

-- Debounced save (coalesces multiple rapid saves into one)
local function schedule_save()
	if save_timer then
		save_timer:stop()
		save_timer:close()
		save_timer = nil
	end

	save_timer = vim.uv.new_timer()
	if save_timer then
		save_timer:start(
			SAVE_DEBOUNCE_MS,
			0,
			vim.schedule_wrap(function()
				save_persistent_state()
				if save_timer then
					save_timer:stop()
					save_timer:close()
					save_timer = nil
				end
			end)
		)
	end
end

-- Initialize state from disk
function M.init()
	local persistent = load_persistent_state()
	for key, value in pairs(persistent) do
		state[key] = value
	end
end

-- Get state value
function M.get(key)
	vim.validate({ key = { key, "string" } })
	return state[key]
end

-- Set state value
function M.set(key, value)
	vim.validate({ key = { key, "string" } })
	state[key] = value

	-- Schedule debounced save if it's a persistent key
	if key:match("^persistent_") or key:match("^initialized_") then
		schedule_save()
	end
end

-- Check if key exists
function M.has(key)
	vim.validate({ key = { key, "string" } })
	return state[key] ~= nil
end

-- Remove state value
function M.remove(key)
	vim.validate({ key = { key, "string" } })
	state[key] = nil
end

-- Clear all state
function M.clear()
	state = {}
	save_persistent_state()
end

-- Clear volatile state (keep persistent)
function M.clear_volatile()
	local persistent = {}
	for key, value in pairs(state) do
		if key:match("^persistent_") or key:match("^initialized_") then
			persistent[key] = value
		end
	end
	state = persistent
end

-- Get all state (for debugging)
function M.get_all()
	return vim.deepcopy(state)
end

-- Track active jobs
function M.add_job(id, info)
	local jobs = state.active_jobs or {}
	jobs[id] = info
	state.active_jobs = jobs
end

function M.remove_job(id)
	local jobs = state.active_jobs or {}
	jobs[id] = nil
	state.active_jobs = jobs
end

function M.get_jobs()
	return state.active_jobs or {}
end

function M.has_active_jobs()
	local jobs = state.active_jobs or {}
	return next(jobs) ~= nil
end

-- Track environment status
function M.set_env_status(language, status)
	state["env_" .. language] = status
	state["env_" .. language .. "_time"] = os.time()
end

function M.get_env_status(language)
	return state["env_" .. language]
end

-- Track package installation
function M.mark_package_installed(language, package)
	local key = "installed_" .. language
	local installed = state[key] or {}
	installed[package] = os.time()
	state[key] = installed
end

function M.is_package_installed(language, package)
	local key = "installed_" .. language
	local installed = state[key] or {}
	return installed[package] ~= nil
end

function M.get_installed_packages(language)
	local key = "installed_" .. language
	return state[key] or {}
end

-- Track last check times
function M.set_last_check(check_type, language)
	local key = "last_check_" .. check_type .. "_" .. language
	state[key] = os.time()
end

function M.get_last_check(check_type, language)
	local key = "last_check_" .. check_type .. "_" .. language
	return state[key]
end

function M.should_check(check_type, language, interval)
	interval = interval or 300 -- 5 minutes default
	local last_check = M.get_last_check(check_type, language)
	if not last_check then
		return true
	end
	return os.time() - last_check > interval
end

-- Session tracking
function M.start_session()
	state.session_start = os.time()
	state.session_id = vim.fn.tempname()
end

function M.get_session_duration()
	if state.session_start then
		return os.time() - state.session_start
	end
	return 0
end

-- Cleanup function for plugin unload
function M.cleanup()
	if save_timer then
		save_timer:stop()
		save_timer:close()
		save_timer = nil
	end
	-- Save any pending state before exit
	save_persistent_state()
end

return M
