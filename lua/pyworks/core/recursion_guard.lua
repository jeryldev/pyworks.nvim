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

-- Constants
local DEFAULT_DEBOUNCE_MS = 500
local DEFAULT_SAFE_TICK_RATE = 1000
local DEFAULT_MAX_RECURSION_DEPTH = 3

-- State tracking for reload operations
local state = {
	reloading_buffers = {},
	global_reload_in_progress = false,
	-- Initialize to negative value so first can_reload() check passes debounce
	last_reload_time = -(DEFAULT_DEBOUNCE_MS + 1),
	original_tick_rate = nil,
	recursion_depth = 0,
}

-- Configuration (can be overridden via M.configure())
local config = {
	debounce_ms = DEFAULT_DEBOUNCE_MS,
	safe_tick_rate = DEFAULT_SAFE_TICK_RATE,
	max_recursion_depth = DEFAULT_MAX_RECURSION_DEPTH,
}

-- Clean up buffer state when buffers are deleted (prevents memory leaks)
local cleanup_augroup = vim.api.nvim_create_augroup("PyworksRecursionGuardCleanup", { clear = true })
vim.api.nvim_create_autocmd("BufDelete", {
	group = cleanup_augroup,
	callback = function(ev)
		state.reloading_buffers[ev.buf] = nil
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
		if vim.g.pyworks_debug then
			vim.notify(
				string.format("[recursion_guard] Blocked: global reload in progress (depth=%d)", state.recursion_depth),
				vim.log.levels.DEBUG
			)
		end
		return false
	end

	-- Check per-buffer lock
	if bufnr and state.reloading_buffers[bufnr] then
		if vim.g.pyworks_debug then
			vim.notify(
				string.format("[recursion_guard] Blocked: buffer %d already reloading", bufnr),
				vim.log.levels.DEBUG
			)
		end
		return false
	end

	-- Check debounce
	local elapsed = now - state.last_reload_time
	if elapsed < config.debounce_ms then
		if vim.g.pyworks_debug then
			vim.notify(
				string.format("[recursion_guard] Blocked: debounce (%dms since last reload)", elapsed),
				vim.log.levels.DEBUG
			)
		end
		return false
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
	state.last_reload_time = vim.uv.now()
	state.recursion_depth = state.recursion_depth + 1

	if bufnr then
		state.reloading_buffers[bufnr] = true
	end

	-- Slow down Molten tick rate during reload to prevent interference
	if vim.g.molten_tick_rate then
		state.original_tick_rate = vim.g.molten_tick_rate
		vim.g.molten_tick_rate = config.safe_tick_rate
	end

	if vim.g.pyworks_debug then
		vim.notify(
			string.format("[recursion_guard] Begin reload: bufnr=%s, depth=%d", tostring(bufnr), state.recursion_depth),
			vim.log.levels.DEBUG
		)
	end

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

		-- Restore original Molten tick rate
		if state.original_tick_rate then
			vim.g.molten_tick_rate = state.original_tick_rate
			state.original_tick_rate = nil
		end
	end

	if vim.g.pyworks_debug then
		vim.notify(
			string.format("[recursion_guard] End reload: bufnr=%s, depth=%d", tostring(bufnr), state.recursion_depth),
			vim.log.levels.DEBUG
		)
	end
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
	-- Set last_reload_time to a value that ensures debounce check passes immediately
	-- Using negative offset ensures first can_reload() after reset returns true
	state.last_reload_time = -(config.debounce_ms + 1)

	if state.original_tick_rate then
		vim.g.molten_tick_rate = state.original_tick_rate
		state.original_tick_rate = nil
	end

	if vim.g.pyworks_debug then
		vim.notify("[recursion_guard] Force reset complete", vim.log.levels.DEBUG)
	end
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
