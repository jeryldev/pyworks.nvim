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
note("ready event seen", ready_events > 0)
note("time to ready (ms)", ready_events > 0 and (vim.uv.now() - start) or "n/a")
note("b:pyworks_kernel_ready", vim.b[buf].pyworks_kernel_ready)

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

print("\n===== SCENARIO RESULTS =====")
for _, line in ipairs(results) do
	print(line)
end
print("\n===== PYWORKS LOG =====")
for _, entry in ipairs(log.entries()) do
	print(log.format_entry(entry))
end
vim.cmd("qa!")
