-- Smart notification system for pyworks.nvim
-- Provides context-aware notifications based on user state

local M = {}

local state = require("pyworks.core.state")

-- Configuration
local config = {
	verbose_first_time = true,
	silent_when_ready = true,
	show_progress = true,
	debug_mode = false,
}

-- Track notification history to avoid duplicates
local notification_history = {}
local history_ttl = 10 -- seconds

-- Check if this is first time for a given context
local function is_first_time(context)
	return not state.get("initialized_" .. context)
end

-- Mark context as initialized
local function mark_initialized(context)
	state.set("initialized_" .. context, true)
end

-- Check if we should suppress duplicate notifications
local function should_suppress(message)
	local now = vim.loop.now()

	-- Check history
	for i = #notification_history, 1, -1 do
		local entry = notification_history[i]

		-- Remove old entries
		if now - entry.time > history_ttl * 1000 then
			table.remove(notification_history, i)
		elseif entry.message == message then
			-- Found duplicate within TTL
			return true
		end
	end

	-- Add to history
	table.insert(notification_history, {
		message = message,
		time = now,
	})

	return false
end

-- Main notification function
function M.notify(message, level, options)
	options = options or {}
	level = level or vim.log.levels.INFO

	-- Check if we should suppress
	if should_suppress(message) and not options.force then
		return
	end

	-- Debug mode - always show
	if config.debug_mode then
		vim.notify("[Pyworks] " .. message, level)
		return
	end

	-- Determine if we should show the notification
	local should_show = false

	-- Check force/always flags first (highest priority)
	if options.force or options.always then
		should_show = true
	elseif options.error then
		should_show = true
		level = vim.log.levels.ERROR
	elseif options.action_required then
		should_show = true
		level = vim.log.levels.WARN
	elseif options.first_time then
		should_show = config.verbose_first_time
	elseif options.progress then
		should_show = config.show_progress
	elseif config.silent_when_ready then
		-- Silent mode when everything is ready
		should_show = false
	else
		-- Default behavior
		should_show = level >= vim.log.levels.WARN
	end

	if should_show then
		vim.notify(message, level)
	end
end

-- Progress notification with optional spinner
local progress_handles = {}

function M.progress_start(id, title, message)
	if not config.show_progress then
		return
	end

	-- Check if we have a progress extension (like fidget.nvim)
	local has_progress = pcall(require, "fidget")

	if has_progress then
		local fidget = require("fidget")
		progress_handles[id] = fidget.progress.handle.create({
			title = title,
			message = message,
			percentage = 0,
		})
	else
		-- Fallback to simple notification
		M.notify(title .. ": " .. message, vim.log.levels.INFO, { progress = true })
	end
end

function M.progress_update(id, message, percentage)
	if not config.show_progress then
		return
	end

	local handle = progress_handles[id]
	if handle then
		handle:report({
			message = message,
			percentage = percentage,
		})
	end
end

function M.progress_finish(id, message)
	if not config.show_progress then
		return
	end

	local handle = progress_handles[id]
	if handle then
		handle:finish()
		progress_handles[id] = nil
	else
		-- Fallback notification
		if message then
			M.notify(message, vim.log.levels.INFO, { progress = true })
		end
	end
end

-- Context-aware notification helpers
function M.notify_first_time(context, message, level)
	if is_first_time(context) then
		M.notify(message, level, { first_time = true })
		mark_initialized(context)
	end
end

function M.notify_missing_packages(packages, language)
	if #packages == 0 then
		return
	end

	local message
	if #packages == 1 then
		message = string.format("[%s] Missing package: %s", language, packages[1])
	else
		message = string.format("[%s] Missing %d packages: %s", language, #packages, table.concat(packages, ", "))
	end

	message = message .. "\nPress <leader>pi to install"

	M.notify(message, vim.log.levels.WARN, { action_required = true })
end

function M.notify_environment_ready(language)
	local context = language .. "_env"
	if is_first_time(context) then
		M.notify(
			string.format("%s environment ready", language:gsub("^%l", string.upper)),
			vim.log.levels.INFO,
			{ first_time = true }
		)
		mark_initialized(context)
	end
end

function M.notify_package_installed(package, language)
	M.notify(string.format("[%s] Installed: %s", language, package), vim.log.levels.INFO, { progress = true })
end

function M.notify_error(message)
	M.notify(message, vim.log.levels.ERROR, { error = true })
end

-- Configure the notification system
function M.configure(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Get current configuration
function M.get_config()
	return config
end

-- Clear notification history
function M.clear_history()
	notification_history = {}
end

-- Debug helpers
function M.set_debug(enabled)
	config.debug_mode = enabled
end

function M.get_history()
	return notification_history
end

return M
