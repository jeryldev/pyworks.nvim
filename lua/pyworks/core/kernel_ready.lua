-- Tracks which Molten kernels have reported themselves ready
--
-- Molten only announces readiness as an edge: it fires User MoltenKernelReady
-- once, at the not-ready -> ready transition, and offers no way to ask "is the
-- kernel ready now?". Miss that edge and there is no way to recover it.
--
-- That matters because anything evaluated before the kernel is ready is
-- silently dropped: Molten reads no kernel message until jupyter_client's
-- wait_for_ready() returns, and that call ends by flushing the IOPub channel,
-- so the cell sits on "* On Hold" forever (issue #10).
--
-- Readiness is therefore recorded per kernel id in module state and set up at
-- plugin load, not when a keymap module happens to be required. Registering the
-- listener from keymaps.lua meant that for .ipynb buffers - where jupytext
-- conversion delays FileType python by seconds - the kernel could report ready
-- before anything of ours was listening.

local M = {}

local log = require("pyworks.core.log")
local utils = require("pyworks.utils")

-- kernel_id -> true, for kernels that have reported ready this session
local ready_kernels = {}

local KERNEL_READY_TIMEOUT_MS = 10000

local function mark_buffers_ready(kernel_id)
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].molten_initialized then
			local buf_kernel = vim.b[bufnr].pyworks_kernel_name
			-- Only claim readiness for the buffer whose kernel reported it;
			-- another buffer's kernel may still be starting up
			if kernel_id == nil or buf_kernel == nil or buf_kernel == kernel_id then
				utils.safe_buf_set_var(bufnr, "pyworks_kernel_ready", true)
			end
		end
	end
end

-- Register the MoltenKernelReady listener. Called at plugin load so the event
-- cannot fire before we are listening.
function M.setup()
	local augroup = vim.api.nvim_create_augroup("PyworksKernelReady", { clear = true })

	vim.api.nvim_create_autocmd("User", {
		group = augroup,
		pattern = "MoltenKernelReady",
		callback = function(ev)
			local kernel_id = ev.data and ev.data.kernel_id
			-- Logged because its *absence* is the diagnosis: with b:kernel_ready
			-- nil and no line here, Molten never reported the kernel ready, which
			-- is a different problem from our latch failing to match
			log.debug("kernel_ready", "MoltenKernelReady received for kernel_id=%s", tostring(kernel_id))
			if kernel_id then
				ready_kernels[kernel_id] = true
			end
			mark_buffers_ready(kernel_id)
		end,
		desc = "Pyworks: record Molten kernel readiness",
	})
end

-- Record a kernel as ready (exposed for tests and for callers that learn about
-- readiness by other means)
function M.mark_ready(kernel_id)
	if kernel_id then
		ready_kernels[kernel_id] = true
	end
	mark_buffers_ready(kernel_id)
end

function M.is_ready(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- Callers reach here from deferred callbacks, so the buffer may be gone;
	-- reading vim.b[<invalid>] would throw where nothing can catch it
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	if vim.b[bufnr].pyworks_kernel_ready == true then
		return true
	end

	-- The event may have fired before this buffer was tagged with its kernel,
	-- so consult the per-kernel record too
	local kernel = vim.b[bufnr].pyworks_kernel_name
	if kernel and ready_kernels[kernel] then
		utils.safe_buf_set_var(bufnr, "pyworks_kernel_ready", true)
		return true
	end

	return false
end

-- Run fn as soon as the kernel is ready (immediately if it already is)
function M.run_when_ready(bufnr, fn, opts)
	opts = opts or {}

	if M.is_ready(bufnr) then
		fn()
		return
	end

	-- the buffer may already be gone; reading vim.b[<invalid>] would throw
	local kernel_name = vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].pyworks_kernel_name or nil
	log.debug("kernel_ready", "waiting for kernel %s on buffer %d", tostring(kernel_name), bufnr)
	vim.notify("Waiting for the kernel to be ready...", vim.log.levels.INFO)

	local done = false
	local function run_once()
		if done then
			return
		end
		done = true
		fn()
	end

	vim.api.nvim_create_autocmd("User", {
		pattern = "MoltenKernelReady",
		once = true,
		callback = function()
			vim.schedule(run_once)
		end,
	})

	-- If the event never arrives the kernel is almost certainly ready already
	-- (a missed edge), so run rather than leave the keypress dead. Kept short:
	-- waiting longer than kernel startup helps nobody.
	local timer = vim.uv.new_timer()
	timer:start(
		opts.timeout_ms or KERNEL_READY_TIMEOUT_MS,
		0,
		vim.schedule_wrap(function()
			if not timer:is_closing() then
				timer:stop()
				timer:close()
			end
			if not done and vim.api.nvim_buf_is_valid(bufnr) then
				log.warn(
					"kernel_ready",
					"kernel never reported ready; running anyway after %dms",
					opts.timeout_ms or KERNEL_READY_TIMEOUT_MS
				)
				run_once()
			end
		end)
	)
end

-- Watch a freshly initialised kernel and speak up if it never reports ready.
--
-- :MoltenInit returning success means only that the command dispatched. Molten
-- starts the kernel on its rplugin host and reports failures there,
-- asynchronously - a kernel that dies on startup, or a connection file that
-- cannot be written, leaves vim.cmd perfectly happy. Pyworks would then set
-- b:molten_initialized, announce "Starting kernel...", and never speak again,
-- which is precisely how issue #10 presents: an infinite "* On Hold" with a
-- healthy interpreter and no error anywhere.
--
-- This does not fix a broken kernel. It converts silence into a diagnosis.
function M.watch(bufnr, kernel_id, opts)
	opts = opts or {}
	local timeout_ms = opts.timeout_ms or KERNEL_READY_TIMEOUT_MS

	local timer = vim.uv.new_timer()
	timer:start(
		timeout_ms,
		0,
		vim.schedule_wrap(function()
			if not timer:is_closing() then
				timer:stop()
				timer:close()
			end

			-- the buffer closing is not a failure, it is the user moving on
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			if M.is_ready(bufnr) then
				return
			end

			-- Captured here, at the moment of failure, because it is the one
			-- signal that separates "Molten never started a kernel" from
			-- "Molten started one and is not polling it": readiness is only
			-- ever noticed from inside the MoltenTick timer's callback
			local tick = require("pyworks.dependencies").molten_tick_timer()

			log.warn(
				"kernel_ready",
				"kernel '%s' did not report ready within %dms (MoltenTick timer running=%s, tick_rate=%s)",
				tostring(kernel_id),
				timeout_ms,
				tostring(tick.running),
				tostring(vim.g.molten_tick_rate)
			)

			if opts.on_timeout then
				opts.on_timeout(kernel_id)
			end
		end)
	)
end

-- Test helper: forget every recorded kernel
function M._reset()
	ready_kernels = {}
end

return M
