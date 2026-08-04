-- Answers one question: does Molten report the kernel ready on this platform,
-- and does a cell submitted afterwards actually complete?
local log = require("pyworks.core.log")
local kernel_ready = require("pyworks.core.kernel_ready")
kernel_ready.setup()

local results = {}
local function note(k, v)
	table.insert(results, string.format("%-34s %s", k .. ":", tostring(v)))
end

-- give setup()'s deferred configure_notebook_handler a chance to register
vim.wait(1500, function()
	return false
end, 100)

local nb = "/work/project/нейророботика/нейророботика_экзамен.ipynb"
note("notebook path is non-ASCII", nb:find("[\128-\255]") ~= nil)

local ready_events = 0
vim.api.nvim_create_autocmd("User", {
	pattern = "MoltenKernelReady",
	callback = function(ev)
		ready_events = ready_events + 1
		note("MoltenKernelReady kernel_id", vim.inspect(ev.data))
	end,
})

vim.cmd("edit " .. vim.fn.fnameescape(nb))
local buf = vim.api.nvim_get_current_buf()
note("buffer lines after open", vim.api.nvim_buf_line_count(buf))
note("filetype after open", vim.bo.filetype)

vim.b[buf].pyworks_kernel_name = "mypjs_python"
local init_ok, init_err = pcall(vim.cmd, "MoltenInit mypjs_python")
note("MoltenInit ok", init_ok)
if not init_ok then
	note("MoltenInit error", init_err)
end
vim.b[buf].molten_initialized = true

-- wait up to 60s for the readiness edge
local start = vim.uv.now()
vim.wait(60000, function()
	return ready_events > 0
end, 250)
local ready_ms = ready_events > 0 and (vim.uv.now() - start) or nil
note("ready event seen", ready_events > 0)
note("time to ready (ms)", ready_ms or "n/a")
note("b:pyworks_kernel_ready", vim.b[buf].pyworks_kernel_ready)

-- The tick-timer check is only trustworthy if a real, working Molten makes it
-- say true. Unit tests use a stand-in vimscript MoltenTick; this is the live
-- kernel that proves the detection is not a false negative waiting to send
-- someone chasing a timer that was there all along.
local dependencies = require("pyworks.dependencies")
local tick = dependencies.molten_tick_timer()
note("MoltenTick timer running", tick.running)
-- The interval is the assertion that matters. Opening the notebook runs the
-- jupytext reload, which used to raise g:molten_tick_rate to 999999; a Molten
-- initialising inside that window latched it and only noticed the kernel 16.7
-- minutes later (issue #10). This must read the real rate, not the reload one.
note("MoltenTick fires every (ms)", tick.interval_ms)
note("molten tick rate", vim.g.molten_tick_rate)
note("molten runtime dir", require("pyworks.core.detector").molten_runtime_dir())
note("runtime dir exists", vim.fn.isdirectory(require("pyworks.core.detector").molten_runtime_dir()) == 1)

-- now run a cell the way pyworks does and watch for completion
local marker = "/work/out/kernel_ran.txt"
pcall(vim.cmd, string.format("MoltenEvaluateArgument open(%q,'w').write('ok')", marker))
vim.wait(30000, function()
	return vim.fn.filereadable(marker) == 1
end, 250)
note("kernel executed the code", vim.fn.filereadable(marker) == 1)

-- and what Molten shows for the cell
local shown = "<none>"
for name, ns in pairs(vim.api.nvim_get_namespaces()) do
	if name == "molten-extmarks" then
		for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
			local d, parts = m[4], {}
			for _, c in ipairs(d and d.virt_text or {}) do
				table.insert(parts, c[1])
			end
			for _, vl in ipairs(d and d.virt_lines or {}) do
				for _, c in ipairs(vl) do
					table.insert(parts, c[1])
				end
			end
			local text = table.concat(parts, "")
			if text:find("Out%[") or text:find("Hold") or text:find("Running") then
				shown = text
			end
		end
	end
end
note("molten virt text", shown)

-- Assertions, so this is a regression net and not just a printout.
--
-- Everything below passed for weeks while issue #10 was live in main: 405 unit
-- tests, green, the entire time. The bug lived between pyworks, Molten's
-- rplugin host and a real kernel, which is a layer unit tests cannot reach.
-- These run nightly.
local MAX_READY_MS = 15000
local MAX_TICK_INTERVAL_MS = 1000

local failures = {}
local function check(label, ok, detail)
	table.insert(
		results,
		string.format("%-34s %s%s", label .. ":", ok and "PASS" or "FAIL", detail and ("  " .. detail) or "")
	)
	if not ok then
		table.insert(failures, label)
	end
end

table.insert(results, "")
check("kernel reported ready", ready_events > 0)
check(
	"ready within budget",
	ready_events > 0 and ready_ms and ready_ms < MAX_READY_MS,
	string.format("%s / %dms", tostring(ready_ms), MAX_READY_MS)
)
check("tick timer exists", tick.running == true)
-- The regression that was issue #10: a timer latched at pyworks' old reload
-- rate is "running" while polling once every 16.7 minutes
check(
	"tick interval is sane",
	tick.interval_ms ~= nil and tick.interval_ms <= MAX_TICK_INTERVAL_MS,
	string.format("%sms / %dms", tostring(tick.interval_ms), MAX_TICK_INTERVAL_MS)
)
check("kernel executed a cell", vim.fn.filereadable(marker) == 1)

print("\n===== SCENARIO RESULTS =====")
for _, line in ipairs(results) do
	print(line)
end
print("\n===== PYWORKS LOG =====")
for _, entry in ipairs(log.entries()) do
	print(log.format_entry(entry))
end

if #failures > 0 then
	print("\nFAILED: " .. table.concat(failures, ", "))
	vim.cmd("cq")
end
print("\nall checks passed")
vim.cmd("qa!")
