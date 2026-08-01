-- Diagnostic logging for pyworks.nvim
--
-- Separate from core/notifications on purpose: a notification interrupts the
-- user now, a log entry is for whoever diagnoses a problem later. Merging them
-- means every change to one degrades the other, which is how 17 developer-only
-- DEBUG messages ended up in the user's notification stream.
--
-- The ring buffer is always on. Asking a user to enable a flag and reproduce
-- costs a round-trip that is often never paid: issue #10 took five exchanges,
-- and the flag we told the reporter to set (vim.g.pyworks_debug_file) only
-- existed in keymaps.lua, so it produced nothing for the path they were on.
-- Recording unconditionally means the history is already there when they write.

local M = {}

local LEVELS = {
	trace = 1,
	debug = 2,
	info = 3,
	warn = 4,
	error = 5,
}

local LEVEL_NAMES = { "TRACE", "DEBUG", "INFO", "WARN", "ERROR" }

local DEFAULTS = {
	level = "debug", -- recorded to the ring
	max_entries = 500,
	file = false,
	file_path = nil, -- defaults to stdpath("log")/pyworks.log
	max_file_bytes = 1024 * 1024,
	redact = true,
}

local config = vim.deepcopy(DEFAULTS)

-- Circular buffer: `entries` holds at most config.max_entries, `next_index`
-- points at the slot to overwrite once full.
local entries = {}
local next_index = 1
local context = {}

local function level_value(name)
	return LEVELS[name] or LEVELS.debug
end

local function default_file_path()
	return vim.fn.stdpath("log") .. "/pyworks.log"
end

local function redact(message)
	if not config.redact then
		return message
	end
	local home = vim.env.HOME
	if home and home ~= "" then
		message = message:gsub(vim.pesc(home), "~")
	end
	return message
end

local function write_to_file(line)
	local path = config.file_path or default_file_path()

	-- Rotate before appending so the file never grows far past the limit
	local size = vim.fn.getfsize(path)
	if size > 0 and size >= config.max_file_bytes then
		pcall(os.rename, path, path .. ".old")
	end

	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		pcall(vim.fn.mkdir, dir, "p")
	end

	local file = io.open(path, "a")
	if not file then
		return
	end
	file:write(line .. "\n")
	file:close()
end

-- Record an entry. Formatting happens only if the level is enabled, so a
-- disabled level costs one comparison and nothing else - the reason this takes
-- a format string plus arguments instead of a finished string.
local function record(level, module, fmt, ...)
	if LEVELS[level] < level_value(config.level) then
		return
	end

	local ok, message = pcall(string.format, fmt, ...)
	if not ok then
		message = tostring(fmt)
	end
	message = redact(message)

	local entry = {
		time = os.time(),
		clock = vim.uv.now(),
		level = level,
		module = module,
		message = message,
		ctx = vim.deepcopy(context),
	}

	entries[next_index] = entry
	next_index = next_index + 1
	if next_index > config.max_entries then
		next_index = 1
	end

	if config.file then
		write_to_file(M.format_entry(entry))
	end
end

function M.trace(module, fmt, ...)
	record("trace", module, fmt, ...)
end

function M.debug(module, fmt, ...)
	record("debug", module, fmt, ...)
end

function M.info(module, fmt, ...)
	record("info", module, fmt, ...)
end

function M.warn(module, fmt, ...)
	record("warn", module, fmt, ...)
end

function M.error(module, fmt, ...)
	record("error", module, fmt, ...)
end

-- Merge key/values into the context attached to subsequent entries
function M.ctx(values)
	vim.validate({ values = { values, "table", true } })
	context = vim.tbl_extend("force", context, values or {})
end

function M.clear_ctx()
	context = {}
end

-- Recorded entries, oldest first
function M.entries()
	local out = {}

	-- Slots after next_index hold the older half once the buffer has wrapped
	for i = next_index, config.max_entries do
		if entries[i] then
			table.insert(out, entries[i])
		end
	end
	for i = 1, next_index - 1 do
		if entries[i] then
			table.insert(out, entries[i])
		end
	end

	return out
end

function M.clear()
	entries = {}
	next_index = 1
end

function M.format_entry(entry)
	local level_name = LEVEL_NAMES[LEVELS[entry.level]] or entry.level:upper()
	local ctx_parts = {}
	for key, value in pairs(entry.ctx or {}) do
		table.insert(ctx_parts, string.format("%s=%s", key, tostring(value)))
	end
	table.sort(ctx_parts)
	local ctx_str = #ctx_parts > 0 and (" {" .. table.concat(ctx_parts, " ") .. "}") or ""

	return string.format(
		"%s %-5s %-16s %s%s",
		os.date("%H:%M:%S", entry.time),
		level_name,
		entry.module or "-",
		entry.message,
		ctx_str
	)
end

function M.configure(opts)
	vim.validate({ opts = { opts, "table", true } })
	config = vim.tbl_extend("force", config, opts or {})

	if config.max_entries < 1 then
		config.max_entries = 1
	end
end

-- Restore defaults (used by tests and :PyworksLog)
function M.reset()
	config = vim.deepcopy(DEFAULTS)
	M.clear()
	M.clear_ctx()
end

function M.get_config()
	return vim.deepcopy(config)
end

return M
