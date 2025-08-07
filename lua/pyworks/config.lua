-- pyworks.nvim - Configuration module
-- Centralized state and configuration management

local M = {}

-- Default configuration
M.defaults = {
	python = {
		preferred_venv_name = ".venv",
		use_uv = true,
	},
	ui = {
		icons = {
			python = "🐍",
			success = "✓",
			error = "✗",
			warning = "⚠️",
			info = "💡",
			progress = "⏳",
		},
	},
	auto_activate_venv = true,
	logging = {
		level = vim.log.levels.INFO,
		show_progress = true,
	},
	-- Molten output configuration
	molten = {
		virt_text_output = false,  -- false = show output in window below cell
		output_virt_lines = false,  -- false = don't use virtual lines
		virt_lines_off_by_1 = false,  -- false = output directly below
		output_win_max_height = 30,
		auto_open_output = true,
		output_win_style = "minimal",
	},
}

-- Current configuration (merged with defaults)
M.current = {}

-- Runtime state
M.state = {
	-- Virtual environment info
	venv = {
		path = nil,
		python_path = nil,
		is_active = false,
		has_uv = nil,
	},
	-- Project info
	project = {
		type = nil,
		cwd = nil,
		setup_completed = false,
	},
	-- Active jobs
	jobs = {},
	-- Progress tracking
	progress = {},
}

-- Merge user config with defaults
function M.setup(user_config)
	M.current = vim.tbl_deep_extend("force", M.defaults, user_config or {})
	return M.current
end

-- Get configuration value
function M.get(key)
	local keys = vim.split(key, ".", { plain = true })
	local value = M.current

	for _, k in ipairs(keys) do
		if type(value) == "table" and value[k] ~= nil then
			value = value[k]
		else
			return nil
		end
	end

	return value
end

-- Get state value
function M.get_state(key)
	local keys = vim.split(key, ".", { plain = true })
	local value = M.state

	for _, k in ipairs(keys) do
		if type(value) == "table" and value[k] ~= nil then
			value = value[k]
		else
			return nil
		end
	end

	return value
end

-- Set state value
function M.set_state(key, val)
	local keys = vim.split(key, ".", { plain = true })
	local current = M.state

	-- Navigate to parent
	for i = 1, #keys - 1 do
		local k = keys[i]
		if type(current[k]) ~= "table" then
			current[k] = {}
		end
		current = current[k]
	end

	-- Set the value
	current[keys[#keys]] = val
end

-- Update virtual environment state
function M.update_venv_state(venv_path)
	if venv_path and vim.fn.isdirectory(venv_path) == 1 then
		M.state.venv.path = venv_path
		M.state.venv.python_path = venv_path .. "/bin/python3"
		M.state.venv.is_active = true

		-- Check for uv
		local venv_bin = venv_path .. "/bin"
		M.state.venv.has_uv = vim.fn.executable(venv_bin .. "/uv") == 1 or vim.fn.executable("uv") == 1
	else
		M.state.venv = {
			path = nil,
			python_path = nil,
			is_active = false,
			has_uv = nil,
		}
	end
end

-- Track active jobs
function M.add_job(id, info)
	M.state.jobs[id] = vim.tbl_extend("force", {
		start_time = vim.loop.hrtime(),
		status = "running",
	}, info or {})
end

function M.update_job(id, status, result)
	if M.state.jobs[id] then
		M.state.jobs[id].status = status
		M.state.jobs[id].result = result
		M.state.jobs[id].end_time = vim.loop.hrtime()
	end
end

function M.remove_job(id)
	M.state.jobs[id] = nil
end

-- Get active jobs
function M.get_active_jobs()
	local active = {}
	for id, job in pairs(M.state.jobs) do
		if job.status == "running" then
			active[id] = job
		end
	end
	return active
end

-- Validate configuration
function M.validate_config(config)
	local ok = true
	local errors = {}

	-- Validate python config
	if config.python then
		if config.python.preferred_venv_name and type(config.python.preferred_venv_name) ~= "string" then
			table.insert(errors, "python.preferred_venv_name must be a string")
			ok = false
		end
		if config.python.use_uv ~= nil and type(config.python.use_uv) ~= "boolean" then
			table.insert(errors, "python.use_uv must be a boolean")
			ok = false
		end
	end

	-- Validate UI config
	if config.ui and config.ui.icons then
		for key, value in pairs(config.ui.icons) do
			if type(value) ~= "string" then
				table.insert(errors, string.format("ui.icons.%s must be a string", key))
				ok = false
			end
		end
	end

	-- Validate auto_activate_venv
	if config.auto_activate_venv ~= nil and type(config.auto_activate_venv) ~= "boolean" then
		table.insert(errors, "auto_activate_venv must be a boolean")
		ok = false
	end

	return ok, errors
end

-- Get icon
function M.icon(name)
	return M.get("ui.icons." .. name) or ""
end

-- Format message with icon
function M.format_message(message, icon_name)
	local icon = M.icon(icon_name)
	return icon .. (icon ~= "" and " " or "") .. message
end

return M
