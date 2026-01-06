-- Caching layer for pyworks.nvim
-- Provides TTL-based caching for expensive operations

local M = {}

-- Cache storage
local cache = {}

-- Mutex flag to prevent concurrent modifications during cleanup
local is_cleaning = false

-- Maximum cache entries to prevent unbounded growth
local MAX_CACHE_SIZE = 1000

-- Default TTL values (in seconds)
local default_ttl = {
	jupytext_check = 3600, -- 1 hour (rarely changes)
	venv_check = 30, -- 30 seconds
	kernel_list = 60, -- 1 minute
	installed_packages = 300, -- 5 minutes
	notebook_metadata = 120, -- 2 minutes
	package_detection = 60, -- 1 minute
	environment_status = 30, -- 30 seconds
}

-- Get TTL for a key type
local function get_ttl(key)
	-- Extract key type from the key
	for key_type, ttl in pairs(default_ttl) do
		if key:match(key_type) then
			return ttl
		end
	end
	-- Default TTL if no match
	return 60
end

-- Get cached value if not expired
function M.get(key)
	local entry = cache[key]
	if not entry then
		return nil
	end

	local now = os.time()
	local ttl = get_ttl(key)

	if now - entry.timestamp > ttl then
		-- Expired, remove from cache
		cache[key] = nil
		return nil
	end

	return entry.value
end

-- Evict oldest entries if cache exceeds max size
local function evict_if_needed()
	-- Count entries
	local count = 0
	for _ in pairs(cache) do
		count = count + 1
	end

	-- If under limit, nothing to do
	if count < MAX_CACHE_SIZE then
		return
	end

	-- Find and remove oldest entries (remove 10% to avoid frequent evictions)
	local entries = {}
	for key, entry in pairs(cache) do
		table.insert(entries, { key = key, timestamp = entry.timestamp })
	end

	-- Sort by timestamp (oldest first)
	table.sort(entries, function(a, b)
		return a.timestamp < b.timestamp
	end)

	-- Remove oldest 10%
	local to_remove = math.floor(count * 0.1)
	to_remove = math.max(to_remove, 1) -- Remove at least 1

	for i = 1, to_remove do
		if entries[i] then
			cache[entries[i].key] = nil
		end
	end
end

-- Set cache value with current timestamp
function M.set(key, value)
	-- Evict old entries if cache is full
	evict_if_needed()

	cache[key] = {
		value = value,
		timestamp = os.time(),
	}
end

-- Check if key exists and is not expired
function M.has(key)
	return M.get(key) ~= nil
end

-- Clear specific cache entry
function M.invalidate(key)
	cache[key] = nil
end

-- Clear all cache entries matching pattern (thread-safe)
function M.invalidate_pattern(pattern)
	-- Collect keys to delete first (safer than modifying during iteration)
	local keys_to_delete = {}
	for key, _ in pairs(cache) do
		if key:match(pattern) then
			table.insert(keys_to_delete, key)
		end
	end

	-- Delete collected keys
	for _, key in ipairs(keys_to_delete) do
		cache[key] = nil
	end
end

-- Clear entire cache
function M.clear()
	cache = {}
end

-- Get cache statistics
function M.stats()
	local count = 0
	local expired = 0
	local now = os.time()

	for key, entry in pairs(cache) do
		count = count + 1
		local ttl = get_ttl(key)
		if now - entry.timestamp > ttl then
			expired = expired + 1
		end
	end

	return {
		total = count,
		expired = expired,
		active = count - expired,
	}
end

-- Clean expired entries (thread-safe)
function M.cleanup()
	-- Prevent concurrent cleanup runs
	if is_cleaning then
		return 0
	end
	is_cleaning = true

	local now = os.time()
	local cleaned = 0

	-- Collect keys to delete first (safer than modifying during iteration)
	local keys_to_delete = {}
	for key, entry in pairs(cache) do
		local ttl = get_ttl(key)
		if now - entry.timestamp > ttl then
			table.insert(keys_to_delete, key)
		end
	end

	-- Delete collected keys
	for _, key in ipairs(keys_to_delete) do
		cache[key] = nil
		cleaned = cleaned + 1
	end

	is_cleaning = false
	return cleaned
end

-- Override default TTL values
function M.configure(ttl_overrides)
	for key, value in pairs(ttl_overrides or {}) do
		if default_ttl[key] then
			default_ttl[key] = value
		end
	end
end

-- Wrap a function with caching
function M.cached(key, fn)
	local cached_value = M.get(key)
	if cached_value ~= nil then
		return cached_value
	end

	local value = fn()
	if value ~= nil then
		M.set(key, value)
	end

	return value
end

-- Periodic cleanup (optional)
local cleanup_timer = nil
function M.start_periodic_cleanup(interval_seconds)
	interval_seconds = interval_seconds or 300 -- 5 minutes default

	if cleanup_timer then
		cleanup_timer:stop()
	end

	cleanup_timer = vim.loop.new_timer()
	cleanup_timer:start(interval_seconds * 1000, interval_seconds * 1000, function()
		vim.schedule(function()
			M.cleanup()
		end)
	end)
end

-- Stop periodic cleanup
function M.stop_periodic_cleanup()
	if cleanup_timer then
		cleanup_timer:stop()
		cleanup_timer = nil
	end
end

return M
