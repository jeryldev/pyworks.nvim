-- Recursion guard for pyworks.nvim
-- Prevents infinite recursion when notebook reload operations trigger autocmds
-- that could cascade back into more reload operations.
--
-- The problem: BufWinEnter -> reload_notebook_buffer -> :edit -> BufReadCmd ->
-- BufEnter -> invalidate_molten_ns_cache -> Meanwhile: MoltenTick (100ms) ->
-- remote#define#request -> events loop back -> E132 maxfuncdepth error
--
-- Solution: Global state tracking with debouncing and Molten tick rate management

local M = {}

local log = require("pyworks.core.log")

-- Constants
local DEFAULT_DEBOUNCE_MS = 500
local DEFAULT_MAX_RECURSION_DEPTH = 3

-- State tracking for reload operations
local state = {
	reloading_buffers = {},
	global_reload_in_progress = false,
	-- bufnr -> last reload timestamp. Was a single global value, which meant
	-- opening a second notebook within the debounce window silently skipped its
	-- conversion even though it is unrelated to the first (C3).
	last_reload_time = {},
	recursion_depth = 0,
}

-- Configuration (can be overridden via M.configure())
local config = {
	debounce_ms = DEFAULT_DEBOUNCE_MS,
	max_recursion_depth = DEFAULT_MAX_RECURSION_DEPTH,
}

-- Clean up buffer state when buffers are deleted (prevents memory leaks)
local cleanup_augroup = vim.api.nvim_create_augroup("PyworksRecursionGuardCleanup", { clear = true })
vim.api.nvim_create_autocmd("BufDelete", {
	group = cleanup_augroup,
	callback = function(ev)
		state.reloading_buffers[ev.buf] = nil
		state.last_reload_time[ev.buf] = nil
	end,
	desc = "Pyworks: Clean up recursion guard state for deleted buffers",
})

-- Check if a reload operation is safe to execute
-- Returns true if safe, false if should be skipped
function M.can_reload(bufnr)
	vim.validate({ bufnr = { bufnr, "number", true } })

	local now = vim.uv.now()

	-- Check global lock
	if state.global_reload_in_progress then
		log.debug("recursion_guard", "blocked: global reload in progress (depth=%d)", state.recursion_depth)
		return false
	end

	-- Check per-buffer lock
	if bufnr and state.reloading_buffers[bufnr] then
		log.debug("recursion_guard", "blocked: buffer %d already reloading", bufnr)
		return false
	end

	-- Check debounce for this buffer only
	local last = bufnr and state.last_reload_time[bufnr] or state.last_reload_time.global
	if last then
		local elapsed = now - last
		if elapsed < config.debounce_ms then
			log.debug("recursion_guard", "blocked: debounce (%dms since last reload)", elapsed)
			return false
		end
	end

	-- Check recursion depth
	if state.recursion_depth >= config.max_recursion_depth then
		vim.notify(
			string.format("[pyworks] Recursion limit reached (%d), aborting reload", state.recursion_depth),
			vim.log.levels.WARN
		)
		return false
	end

	return true
end

-- Begin a reload operation (call before reload_notebook_buffer)
-- Returns a release function that MUST be called when done
function M.begin_reload(bufnr)
	vim.validate({ bufnr = { bufnr, "number", true } })

	state.global_reload_in_progress = true
	state.last_reload_time[bufnr or "global"] = vim.uv.now()
	state.recursion_depth = state.recursion_depth + 1

	if bufnr then
		state.reloading_buffers[bufnr] = true
	end

	-- The tick rate is deliberately left alone. Raising it here to keep Molten
	-- quiet during a reload could not be made safe: Molten reads
	-- g:molten_tick_rate exactly once, when its host initialises, and bakes it
	-- into timer_start(). A Molten that initialised inside the window kept a
	-- timer firing every 16.7 minutes while the variable read a healthy 100
	-- afterwards, so a working kernel went unnoticed for half an hour and every
	-- cell sat on "* On Hold" (issue #10). Restoring the variable does not
	-- unwind the timer.
	--
	-- Nothing replaces it: the fork pyworks ships carries a MoltenTick
	-- reentrancy guard, which is the interference this was working around, and
	-- :checkhealth warns anyone running a Molten without it.

	log.debug("recursion_guard", "begin reload: bufnr=%s, depth=%d", tostring(bufnr), state.recursion_depth)

	-- Return release function
	return function()
		M.end_reload(bufnr)
	end
end

-- End a reload operation (restores state)
function M.end_reload(bufnr)
	vim.validate({ bufnr = { bufnr, "number", true } })

	state.recursion_depth = math.max(0, state.recursion_depth - 1)

	if bufnr then
		state.reloading_buffers[bufnr] = nil
	end

	-- Only release global lock when all reloads complete
	if state.recursion_depth == 0 then
		state.global_reload_in_progress = false
	end

	log.debug("recursion_guard", "end reload: bufnr=%s, depth=%d", tostring(bufnr), state.recursion_depth)
end

-- Check if any reload is currently in progress (for use by other modules)
function M.is_reloading()
	return state.global_reload_in_progress
end

-- Check if a specific buffer is being reloaded
function M.is_buffer_reloading(bufnr)
	vim.validate({ bufnr = { bufnr, "number" } })
	return state.reloading_buffers[bufnr] == true
end

-- Force reset all state (emergency use only, e.g., after errors)
function M.force_reset()
	state.reloading_buffers = {}
	state.global_reload_in_progress = false
	state.recursion_depth = 0
	state.last_reload_time = {}

	log.debug("recursion_guard", "force reset complete")
end

-- Get current state for debugging
function M.get_state()
	return vim.deepcopy(state)
end

-- Configure the guard (optional)
function M.configure(opts)
	vim.validate({ opts = { opts, "table", true } })
	if opts then
		config = vim.tbl_deep_extend("force", config, opts)
	end
end

-- User command to reset the guard if stuck
vim.api.nvim_create_user_command("PyworksResetReloadGuard", function()
	M.force_reset()
	vim.notify("[pyworks] Reload guard reset", vim.log.levels.INFO)
end, { desc = "Reset pyworks notebook reload guard (use if notebooks won't reload)" })

return M
