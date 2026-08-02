-- Smart notification system for pyworks.nvim
-- Provides context-aware notifications based on user state

local M = {}

local state = require("pyworks.core.state")

-- Constants
local HISTORY_TTL_SECONDS = 10 -- Time-to-live for notification deduplication
local MAX_HISTORY_SIZE = 100 -- Maximum notifications to track (prevents unbounded growth)

-- Configuration
local config = {
	verbose_first_time = true,
	silent_when_ready = true,
	show_progress = true,
	debug_mode = false,
}

-- Track notification history to avoid duplicates
local notification_history = {}

-- Check if this is first time for a given context
local function is_first_time(context)
	return not state.get(state.KEYS.INITIALIZED .. context)
end

-- Mark context as initialized
local function mark_initialized(context)
	state.set(state.KEYS.INITIALIZED .. context, true)
end

-- Check if we should suppress duplicate notifications
local function should_suppress(message)
	local now = vim.uv.now()

	-- Collect indices to remove (expired entries)
	local to_remove = {}
	local found_duplicate = false

	for i = #notification_history, 1, -1 do
		local entry = notification_history[i]
		if now - entry.time > HISTORY_TTL_SECONDS * 1000 then
			table.insert(to_remove, i)
		elseif entry.message == message then
			found_duplicate = true
		end
	end

	-- Remove expired entries (already in reverse order)
	for _, i in ipairs(to_remove) do
		table.remove(notification_history, i)
	end

	if found_duplicate then
		return true
	end

	-- Enforce max size (remove oldest if at limit)
	while #notification_history >= MAX_HISTORY_SIZE do
		table.remove(notification_history, 1)
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
	--
	-- Warnings and errors are never suppressed. silent_when_ready used to catch
	-- them first, so "Ignoring stale kernel...", "No venv for ..." and "Notebook
	-- opened in JSON view" were invisible with the default config - the plugin
	-- quietly withheld exactly the messages that explain a broken setup.
	if options.error then
		level = vim.log.levels.ERROR
	elseif options.action_required then
		level = vim.log.levels.WARN
	end

	local always_show = options.force or options.always or options.error or options.action_required
	local should_show

	if always_show or level >= vim.log.levels.WARN then
		should_show = true
	elseif options.first_time then
		should_show = config.verbose_first_time
	elseif options.progress then
		should_show = config.show_progress
	else
		-- Routine INFO chatter stays quiet once things are working
		should_show = not config.silent_when_ready
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

-- Announce that an environment is ready, at most once per project.
--
-- The context used to be the language alone, and the flag is persisted, so
-- after the first successful setup on a machine this message never appeared
-- again in any project.
function M.notify_environment_ready(language, project_dir)
	local context = language .. "_env"
	if project_dir and project_dir ~= "" then
		context = context .. "_" .. project_dir
	end
	if is_first_time(context) then
		-- Name the project: the message is per project now, and two projects
		-- would otherwise produce identical text that the 10s dedup collapses
		local suffix = ""
		if project_dir and project_dir ~= "" then
			suffix = string.format(" (%s)", vim.fn.fnamemodify(project_dir, ":t"))
		end
		M.notify(
			string.format("%s environment ready%s", language:gsub("^%l", string.upper), suffix),
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
