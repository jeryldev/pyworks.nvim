-- Reproduces issue #10: a Molten that latches pyworks' reload tick rate.
--
-- Molten reads g:molten_tick_rate exactly once, when its host initialises, and
-- bakes it into timer_start():
--
--     self.timer = self.nvim.eval(
--         f"timer_start({self.options.tick_rate}, 'MoltenTick', {{'repeat': -1}})"
--     )
--
-- pyworks' recursion guard raises that variable to 999999 for the duration of a
-- jupytext reload and restores it afterwards. If Molten initialises inside that
-- window it keeps a timer firing every 999999ms - 16.7 minutes - while
-- g:molten_tick_rate reads a perfectly healthy 100 forever after.
--
-- Readiness is only ever noticed inside that timer's callback, so a completely
-- healthy kernel goes unnoticed for tens of minutes. The reporter's kernel was
-- noticed 1999 seconds after MoltenInit; two ticks of 999999ms is 1999.998.
--
-- Run with LATCH=1 to initialise inside the window, unset to compare.

local dependencies = require("pyworks.dependencies")
local kernel_ready = require("pyworks.core.kernel_ready")
kernel_ready.setup()

local latch = vim.env.LATCH == "1"
local results = {}
local function note(k, v)
	table.insert(results, string.format("%-32s %s", k .. ":", tostring(v)))
end

vim.wait(1500, function()
	return false
end, 100)

note("mode", latch and "init inside the reload window" or "control")

-- what pyworks does around a jupytext reload
vim.g.molten_tick_rate = 100
if latch then
	vim.g.molten_tick_rate = 999999
end

local ready_seen = false
vim.api.nvim_create_autocmd("User", {
	pattern = "MoltenKernelReady",
	callback = function()
		ready_seen = true
	end,
})

vim.cmd(
	"edit "
		.. vim.fn.fnameescape(
			"/work/project/нейророботика/нейророботика_экзамен.ipynb"
		)
)
local buf = vim.api.nvim_get_current_buf()
pcall(vim.cmd, "MoltenInit mypjs_python")

-- the guard restores the variable, but Molten has already read it
vim.g.molten_tick_rate = 100

local timer = dependencies.molten_tick_timer()
note("g:molten_tick_rate after restore", vim.g.molten_tick_rate)
note("MoltenTick timer running", timer.running)
note("timer fires every (ms)", timer.interval_ms)

local start = vim.uv.now()
vim.wait(45000, function()
	return ready_seen
end, 250)
note("ready within 45s", ready_seen)
note("time to ready (ms)", ready_seen and (vim.uv.now() - start) or "not within 45s")
note("b:pyworks_kernel_ready", vim.b[buf].pyworks_kernel_ready)

if timer.interval_ms and timer.interval_ms > 1000 then
	note(
		"VERDICT",
		string.format("latched %dms - readiness needs ~%.1f min", timer.interval_ms, timer.interval_ms / 60000)
	)
end

-- Asserted, not just printed, because this is what keeps the *detector* honest.
--
-- A tick-interval check that silently stopped working would report a healthy
-- 100ms on a latched timer and send the next reporter chasing the wrong thing -
-- which is exactly how issue #10 stayed open for six rounds. In LATCH mode the
-- run is expected to look broken; if it looks healthy, the detection has rotted.
local failures = {}
local function check(label, ok, detail)
	table.insert(
		results,
		string.format("%-32s %s%s", label .. ":", ok and "PASS" or "FAIL", detail and ("  " .. detail) or "")
	)
	if not ok then
		table.insert(failures, label)
	end
end

table.insert(results, "")
if latch then
	check(
		"latched interval is visible",
		timer.interval_ms == 999999,
		string.format("saw %sms, expected 999999", tostring(timer.interval_ms))
	)
	check("latched kernel goes unnoticed", not ready_seen)
else
	check("control interval is sane", timer.interval_ms ~= nil and timer.interval_ms <= 1000)
	check("control kernel is noticed", ready_seen)
end

print("\n===== TICK LATCH RESULTS =====")
for _, line in ipairs(results) do
	print(line)
end

if #failures > 0 then
	print("\nFAILED: " .. table.concat(failures, ", "))
	vim.cmd("cq")
end
print("\nall checks passed")
vim.cmd("qa!")
