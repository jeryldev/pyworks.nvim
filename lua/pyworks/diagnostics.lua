-- Diagnostic module for pyworks.nvim
local M = {}

function M.run_diagnostics()
	local report = {}

	-- Check current working directory
	table.insert(report, "=== Pyworks Diagnostics ===")
	table.insert(report, "")
	table.insert(report, "Working Directory: " .. vim.fn.getcwd())

	-- Check for .venv
	local venv_path = ".venv"
	local has_venv = vim.fn.isdirectory(venv_path) == 1
	table.insert(report, "Virtual Environment (.venv): " .. (has_venv and "EXISTS" or "NOT FOUND"))

	if has_venv then
		-- Check for Python in venv
		local python_paths = {
			".venv/bin/python",
			".venv/bin/python3",
		}
		for _, path in ipairs(python_paths) do
			local exists = vim.fn.executable(path) == 1
			table.insert(report, "  " .. path .. ": " .. (exists and "FOUND" or "NOT FOUND"))
		end

		-- Check for pip
		local pip_path = ".venv/bin/pip"
		local has_pip = vim.fn.executable(pip_path) == 1
		table.insert(report, "  " .. pip_path .. ": " .. (has_pip and "FOUND" or "NOT FOUND"))

		-- Check for uv
		local uv_path = ".venv/bin/uv"
		local has_uv = vim.fn.executable(uv_path) == 1
		table.insert(report, "  " .. uv_path .. ": " .. (has_uv and "FOUND" or "NOT FOUND"))
	end

	-- Check system Python
	table.insert(report, "")
	table.insert(report, "System Python:")
	local system_pythons = {
		{ "python3", vim.fn.exepath("python3") },
		{ "python", vim.fn.exepath("python") },
	}
	for _, item in ipairs(system_pythons) do
		local cmd = item[1]
		local path = item[2]
		if path ~= "" then
			table.insert(report, "  " .. cmd .. ": " .. path)
			-- Get version
			local version = vim.fn.system(cmd .. " --version 2>&1")
			version = version:gsub("\n", "")
			table.insert(report, "    Version: " .. version)
		else
			table.insert(report, "  " .. cmd .. ": NOT FOUND")
		end
	end

	-- Check uv
	table.insert(report, "")
	table.insert(report, "UV Package Manager:")
	if vim.fn.executable("uv") == 1 then
		table.insert(report, "  uv: " .. vim.fn.exepath("uv"))
		local version = vim.fn.system("uv --version 2>&1")
		version = version:gsub("\n", "")
		table.insert(report, "  Version: " .. version)
	else
		table.insert(report, "  uv: NOT FOUND")
	end

	-- Check configuration
	table.insert(report, "")
	table.insert(report, "Configuration:")
	local ok, pyworks = pcall(require, "pyworks")
	if ok then
		local config = pyworks.get_config()
		if config and config.python then
			table.insert(report, "  use_uv: " .. tostring(config.python.use_uv))
			table.insert(report, "  preferred_venv_name: " .. (config.python.preferred_venv_name or ".venv"))
		end
	end

	-- Test pip install command
	if has_venv and vim.fn.executable(".venv/bin/pip") == 1 then
		table.insert(report, "")
		table.insert(report, "Testing pip command:")
		local test_cmd = ".venv/bin/pip --version"
		table.insert(report, "  Command: " .. test_cmd)
		local result = vim.fn.system(test_cmd)
		if vim.v.shell_error == 0 then
			result = result:gsub("\n", "")
			table.insert(report, "  Result: " .. result)
		else
			table.insert(report, "  ERROR: pip command failed")
			table.insert(report, "  Output: " .. result)
		end
	end

	-- Display report
	vim.notify(table.concat(report, "\n"), vim.log.levels.INFO)

	-- Also save to a buffer for easier reading
	vim.cmd("new")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, report)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_name(buf, "Pyworks Diagnostics")
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

-- Create diagnostic command
vim.api.nvim_create_user_command("PyworksDiagnostics", function()
	M.run_diagnostics()
end, {
	desc = "Run Pyworks diagnostics to check environment setup",
})

return M

