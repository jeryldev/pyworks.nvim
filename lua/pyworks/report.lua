-- Bug-report generation for pyworks.nvim
--
-- Issue #10 took five round-trips to collect :MoltenInfo, the kernelspec list,
-- kernel.json, :checkhealth provider and :messages - all of which the plugin
-- could read itself. :PyworksReport emits the lot as one paste-ready block.
--
-- Rules: redact $HOME by default, never include file contents.

local M = {}

local log = require("pyworks.core.log")

local LOG_TAIL = 100

local function redact_path(text, enabled)
	if not enabled then
		return text
	end
	local home = vim.env.HOME
	if home and home ~= "" then
		text = text:gsub(vim.pesc(home), "~")
	end
	return text
end

local function section(lines, title)
	table.insert(lines, "")
	table.insert(lines, "## " .. title)
end

local function kv(lines, key, value)
	table.insert(lines, string.format("%-22s %s", key .. ":", tostring(value)))
end

local function plugin_commit()
	local root = debug.getinfo(1, "S").source:sub(2):gsub("/lua/pyworks/report%.lua$", "")
	local ok, result = pcall(function()
		return vim.system({ "git", "-C", root, "rev-parse", "--short", "HEAD" }, { text = true }):wait()
	end)
	if ok and result and result.code == 0 then
		return vim.trim(result.stdout)
	end
	return "unknown"
end

local function environment_section(lines, project_dir)
	section(lines, "Environment")
	kv(lines, "pyworks commit", plugin_commit())
	kv(lines, "nvim", vim.trim(vim.api.nvim_exec2("version", { output = true }).output:match("[^\n]+") or "?"))
	kv(lines, "os", vim.uv.os_uname().sysname .. " " .. vim.uv.os_uname().release)
	kv(lines, "project root", project_dir)

	local ok, python = pcall(require, "pyworks.languages.python")
	if not ok then
		return
	end
	local probe = project_dir .. "/probe.py"
	kv(lines, "venv present", python.has_venv(probe))
	local python_path = python.get_python_path(probe)
	kv(lines, "venv python", python_path or "none")
	if python_path then
		local ver_ok, ver = pcall(function()
			return vim.system({ python_path, "--version" }, { text = true }):wait()
		end)
		if ver_ok and ver and ver.code == 0 then
			kv(lines, "python version", vim.trim(ver.stdout ~= "" and ver.stdout or ver.stderr))
		end
	end
	kv(lines, "uv available", vim.fn.executable("uv") == 1)
	kv(lines, "python3_host_prog", vim.g.python3_host_prog or "unset")
end

local function kernels_section(lines, project_dir)
	section(lines, "Kernels")

	local ok, detector = pcall(require, "pyworks.core.detector")
	if not ok then
		table.insert(lines, "detector unavailable")
		return
	end

	local specs = detector.get_kernelspecs()
	if not specs then
		table.insert(lines, "kernel list unavailable (jupyter not on PATH or failed)")
		return
	end

	for name, spec in pairs(specs) do
		local argv = spec.spec and spec.spec.argv or {}
		local interpreter = argv[1] or "?"
		local exists = vim.fn.executable(interpreter) == 1
		-- The check that decides whether a kernel can ever start (issue #10)
		table.insert(lines, string.format("%-24s interpreter exists=%-5s %s", name, tostring(exists), interpreter))
	end

	local stale = detector.list_stale_kernels(specs)
	if #stale > 0 then
		table.insert(lines, "")
		for _, kernel in ipairs(stale) do
			table.insert(lines, string.format("STALE: %s -> %s", kernel.name, kernel.python))
		end
	end

	local buf = vim.api.nvim_get_current_buf()
	kv(lines, "b:molten_initialized", tostring(vim.b[buf].molten_initialized))
	kv(lines, "b:kernel_ready", tostring(vim.b[buf].pyworks_kernel_ready))
	kv(lines, "b:kernel_name", tostring(vim.b[buf].pyworks_kernel_name))
end

local function packages_section(lines, project_dir)
	section(lines, "Packages")

	local ok, python = pcall(require, "pyworks.languages.python")
	if not ok then
		table.insert(lines, "python module unavailable")
		return
	end

	local probe = project_dir .. "/probe.py"
	local essentials = python.get_essentials()
	table.insert(lines, "essentials: " .. table.concat(essentials, ", "))

	if not python.has_venv(probe) then
		table.insert(lines, "no venv - nothing installed")
		return
	end

	local installed_ok, installed = pcall(python.get_installed_packages, probe)
	if not installed_ok or type(installed) ~= "table" then
		table.insert(lines, "could not list installed packages")
		return
	end
	table.insert(lines, string.format("installed package count: %d", #installed))

	local present = {}
	for _, pkg in ipairs(installed) do
		present[pkg:lower()] = true
	end
	local missing = {}
	for _, pkg in ipairs(essentials) do
		if not present[pkg:lower()] then
			table.insert(missing, pkg)
		end
	end
	table.insert(lines, "essentials not found by name: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
end

local function health_section(lines)
	section(lines, "Health")
	local ok, health = pcall(require, "pyworks.health")
	if not ok then
		table.insert(lines, "health module unavailable")
		return
	end

	local captured = {}
	local real = vim.health
	vim.health = setmetatable({}, {
		__index = function(_, key)
			return function(msg, advice)
				if key == "start" then
					table.insert(captured, "-- " .. tostring(msg))
				else
					table.insert(captured, string.format("[%s] %s", key, tostring(msg)))
					if type(advice) == "table" then
						for _, line in ipairs(advice) do
							table.insert(captured, "      " .. tostring(line))
						end
					end
				end
			end
		end,
	})
	pcall(health.check)
	vim.health = real

	vim.list_extend(lines, captured)
end

local function log_section(lines)
	section(lines, "Recent log")
	local entries = log.entries()
	local start = math.max(1, #entries - LOG_TAIL + 1)
	if #entries == 0 then
		table.insert(lines, "(no entries)")
		return
	end
	for i = start, #entries do
		table.insert(lines, log.format_entry(entries[i]))
	end
end

-- Build the report as a single string
function M.generate(opts)
	opts = opts or {}
	local redact = opts.redact ~= false

	local project_dir = opts.project_dir
	if not project_dir then
		local ok, utils = pcall(require, "pyworks.utils")
		project_dir = ok and (utils.get_project_paths(vim.api.nvim_buf_get_name(0))) or vim.fn.getcwd()
	end

	local lines = { "# pyworks report" }
	pcall(environment_section, lines, project_dir)
	pcall(kernels_section, lines, project_dir)
	pcall(packages_section, lines, project_dir)
	pcall(health_section, lines)
	pcall(log_section, lines)

	return redact_path(table.concat(lines, "\n"), redact)
end

local function open_scratch(title, text)
	vim.cmd("new")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].modifiable = false
	pcall(vim.api.nvim_buf_set_name, buf, title)
	return buf
end

function M.setup_commands()
	vim.api.nvim_create_user_command("PyworksReport", function(cmd)
		local text = M.generate({ redact = not cmd.bang })
		open_scratch("Pyworks Report", text)
		pcall(vim.fn.setreg, "+", text)
		vim.notify("Report copied to clipboard (paste into the issue)", vim.log.levels.INFO)
	end, { bang = true, desc = "Generate a paste-ready pyworks bug report (! to keep home paths)" })

	vim.api.nvim_create_user_command("PyworksLog", function(cmd)
		if cmd.args == "clear" then
			log.clear()
			vim.notify("Pyworks log cleared", vim.log.levels.INFO)
			return
		end
		local entries = log.entries()
		local lines = {}
		for _, entry in ipairs(entries) do
			table.insert(lines, log.format_entry(entry))
		end
		if #lines == 0 then
			lines = { "(no log entries)" }
		end
		open_scratch("Pyworks Log", table.concat(lines, "\n"))
	end, {
		nargs = "?",
		complete = function()
			return { "clear" }
		end,
		desc = "Show the pyworks diagnostic log (:PyworksLog clear to reset)",
	})
end

return M
