-- Diagnostic module for pyworks.nvim
local M = {}

local error_handler = require("pyworks.core.error_handler")

-- Check if a plugin is installed via lazy.nvim
local function is_plugin_installed(plugin_name)
	local lazy_ok, lazy = pcall(require, "lazy.core.config")
	if lazy_ok and lazy.plugins and lazy.plugins[plugin_name] then
		return true
	end
	return false
end

-- Check plugin dependencies
local function check_plugin_dependencies()
	local results = {}

	-- molten-nvim
	if is_plugin_installed("molten-nvim") then
		if vim.fn.exists(":MoltenInit") == 2 then
			table.insert(results, "  molten-nvim: OK (command available)")
		else
			table.insert(results, "  molten-nvim: INSTALLED but not registered (restart may be needed)")
		end
	else
		table.insert(results, "  molten-nvim: NOT INSTALLED")
	end

	-- jupytext.nvim
	if is_plugin_installed("jupytext.nvim") then
		local ok = pcall(require, "jupytext")
		if ok then
			table.insert(results, "  jupytext.nvim: OK")
		else
			table.insert(results, "  jupytext.nvim: INSTALLED but not configured")
		end
	else
		table.insert(results, "  jupytext.nvim: NOT INSTALLED")
	end

	-- image.nvim
	if is_plugin_installed("image.nvim") then
		local ok, img = pcall(require, "image")
		if ok then
			if img.state and img.state.backend then
				table.insert(results, "  image.nvim: OK (" .. img.state.backend .. " backend)")
			else
				table.insert(results, "  image.nvim: INSTALLED but not initialized")
			end
		else
			table.insert(results, "  image.nvim: INSTALLED but not configured")
		end
	else
		table.insert(results, "  image.nvim: NOT INSTALLED")
	end

	return results
end

-- Check Python dependencies
local function check_python_dependencies()
	local results = {}
	local python_cmd = vim.g.python3_host_prog or "python3"
	local python_deps = { "pynvim", "jupyter_client", "ipykernel", "jupytext" }

	for _, dep in ipairs(python_deps) do
		local handle = io.popen(string.format("%s -c 'import %s' 2>&1", python_cmd, dep))
		if handle then
			local result = handle:read("*a")
			handle:close()
			if result == "" then
				table.insert(results, string.format("  %s: OK", dep))
			else
				table.insert(results, string.format("  %s: NOT INSTALLED", dep))
			end
		end
	end

	-- Check jupytext CLI separately
	local handle = io.popen("which jupytext 2>&1")
	if handle then
		local result = handle:read("*a")
		handle:close()
		if result ~= "" and not result:match("not found") then
			table.insert(results, "  jupytext CLI: OK (in PATH)")
		else
			table.insert(results, "  jupytext CLI: NOT IN PATH")
		end
	end

	return results
end

function M.run_diagnostics()
	local ok, _ = error_handler.protected_call(function()
		return {}
	end, "Diagnostics failed")

	if not ok then
		return
	end

	local report = {}

	-- Header
	table.insert(report, "=== Pyworks Diagnostics ===")
	table.insert(report, "")

	-- Working directory
	table.insert(report, "Working Directory: " .. vim.fn.getcwd())
	table.insert(report, "")

	-- Virtual Environment
	table.insert(report, "Virtual Environment:")
	local venv_path = ".venv"
	local has_venv = vim.fn.isdirectory(venv_path) == 1
	table.insert(report, "  .venv: " .. (has_venv and "EXISTS" or "NOT FOUND"))

	if has_venv then
		local python_paths = { ".venv/bin/python", ".venv/bin/python3" }
		for _, path in ipairs(python_paths) do
			local exists = vim.fn.executable(path) == 1
			if exists then
				table.insert(report, "  " .. path .. ": FOUND")
				break
			end
		end
		table.insert(
			report,
			"  .venv/bin/pip: " .. (vim.fn.executable(".venv/bin/pip") == 1 and "FOUND" or "NOT FOUND")
		)
	end

	-- System Python
	table.insert(report, "")
	table.insert(report, "System Python:")
	local python_path = vim.fn.exepath("python3")
	if python_path ~= "" then
		table.insert(report, "  python3: " .. python_path)
		local version = vim.fn.system("python3 --version 2>&1"):gsub("\n", "")
		table.insert(report, "  Version: " .. version)
	else
		table.insert(report, "  python3: NOT FOUND")
	end

	-- UV Package Manager
	table.insert(report, "")
	table.insert(report, "UV Package Manager:")
	if vim.fn.executable("uv") == 1 then
		table.insert(report, "  uv: " .. vim.fn.exepath("uv"))
		local version = vim.fn.system("uv --version 2>&1"):gsub("\n", "")
		table.insert(report, "  Version: " .. version)
	else
		table.insert(report, "  uv: NOT FOUND")
	end

	-- Plugin Dependencies
	table.insert(report, "")
	table.insert(report, "Plugin Dependencies:")
	local plugin_results = check_plugin_dependencies()
	for _, line in ipairs(plugin_results) do
		table.insert(report, line)
	end

	-- Python Dependencies
	table.insert(report, "")
	table.insert(report, "Python Dependencies:")
	local python_results = check_python_dependencies()
	for _, line in ipairs(python_results) do
		table.insert(report, line)
	end

	-- Configuration
	table.insert(report, "")
	table.insert(report, "Configuration:")
	local config_ok, pyworks = pcall(require, "pyworks")
	if config_ok then
		local config = pyworks.get_config()
		if config and config.python then
			table.insert(report, "  use_uv: " .. tostring(config.python.use_uv))
			table.insert(report, "  preferred_venv_name: " .. (config.python.preferred_venv_name or ".venv"))
		end
	end

	-- Cache Stats
	table.insert(report, "")
	table.insert(report, "Cache:")
	local cache_ok, cache = pcall(require, "pyworks.core.cache")
	if cache_ok then
		local stats = cache.stats()
		table.insert(
			report,
			string.format("  Entries: %d total | %d active | %d expired", stats.total, stats.active, stats.expired)
		)
	end

	-- Display in new buffer
	vim.cmd("new")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, report)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.api.nvim_buf_set_name(buf, "Pyworks Diagnostics")
	vim.bo[buf].modifiable = false

	vim.notify("Diagnostics complete - see buffer for details", vim.log.levels.INFO)
end

-- Create diagnostic command
vim.api.nvim_create_user_command("PyworksDiagnostics", function()
	M.run_diagnostics()
end, {
	desc = "Run Pyworks diagnostics to check environment setup",
})

return M
