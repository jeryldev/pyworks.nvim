describe("cell_engine", function()
	local cell_engine

	before_each(function()
		package.loaded["pyworks.core.cell_engine"] = nil
		cell_engine = require("pyworks.core.cell_engine")
	end)

	describe("find_cell_boundaries", function()
		it("should find cell start and end from cursor position", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"import numpy as np",
				"x = 1",
				"# %%",
				"y = 2",
			})

			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			local start_line, end_line = cell_engine.find_cell_boundaries()

			assert.equals(2, start_line)
			assert.equals(3, end_line)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should handle last cell extending to end of file", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"# %%",
				"y = 2",
				"z = 3",
			})

			vim.api.nvim_win_set_cursor(0, { 4, 0 })
			local start_line, end_line = cell_engine.find_cell_boundaries()

			assert.equals(4, start_line)
			assert.equals(5, end_line)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should return nil for empty cell", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"# %%",
			})

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			local start_line, end_line = cell_engine.find_cell_boundaries()

			assert.is_nil(start_line)
			assert.is_nil(end_line)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("count_cells", function()
		it("should count all cell markers in buffer", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"# %%",
				"y = 2",
				"# %% [markdown]",
				"# Some text",
			})

			local count = cell_engine.count_cells(bufnr)
			assert.equals(3, count)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should return 0 for buffer with no cells", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"x = 1",
				"y = 2",
			})

			local count = cell_engine.count_cells(bufnr)
			assert.equals(0, count)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("get_cell_positions", function()
		it("should return line numbers of all cell markers", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"# %%",
				"y = 2",
				"# %%",
				"z = 3",
			})

			local positions = cell_engine.get_cell_positions(bufnr)
			assert.same({ 1, 3, 5 }, positions)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("is_markdown_cell", function()
		it("should detect markdown cells", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %% [markdown]",
				"# Some text",
				"# %%",
				"x = 1",
			})

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			assert.is_true(cell_engine.is_markdown_cell())

			vim.api.nvim_win_set_cursor(0, { 4, 0 })
			assert.is_false(cell_engine.is_markdown_cell())

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("get_cell_pattern", function()
		it("should return default pattern", function()
			local pattern = cell_engine.get_cell_pattern()
			assert.equals("^# %%%%", pattern)
		end)
	end)

	describe("navigation", function()
		it("next_cell should move cursor past the next marker", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"# %%",
				"y = 2",
			})
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			local found = cell_engine.next_cell()
			assert.is_true(found)

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(4, cursor[1])

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("next_cell should return false at last cell", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local found = cell_engine.next_cell()
			assert.is_false(found)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("prev_cell should move to the previous cell content", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"# %%",
				"y = 2",
			})
			vim.api.nvim_win_set_cursor(0, { 4, 0 })

			local found = cell_engine.prev_cell()
			assert.is_true(found)

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(2, cursor[1])

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("cell insertion", function()
		it("insert_cell_below should add a cell marker after current cell", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			cell_engine.insert_cell_below()

			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local count = 0
			for _, line in ipairs(lines) do
				if line:match("^# %%") then
					count = count + 1
				end
			end
			assert.equals(2, count)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("insert_cell_above should add a cell marker before current cell", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			cell_engine.insert_cell_above()

			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local count = 0
			for _, line in ipairs(lines) do
				if line:match("^# %%") then
					count = count + 1
				end
			end
			assert.equals(2, count)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("cell operations", function()
		it("toggle_cell_type should switch code to markdown", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local toggled = cell_engine.toggle_cell_type()
			assert.is_true(toggled)

			local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
			assert.equals("# %% [markdown]", first_line)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("toggle_cell_type should switch markdown to code", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %% [markdown]",
				"# Some text",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			cell_engine.toggle_cell_type()

			local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
			assert.equals("# %%", first_line)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("merge_cell_below should remove next marker", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"# %%",
				"y = 2",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local merged = cell_engine.merge_cell_below()
			assert.is_true(merged)

			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local count = 0
			for _, line in ipairs(lines) do
				if line:match("^# %%") then
					count = count + 1
				end
			end
			assert.equals(1, count)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("split_cell should insert marker at cursor", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"y = 2",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			cell_engine.split_cell()

			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local count = 0
			for _, line in ipairs(lines) do
				if line:match("^# %%") then
					count = count + 1
				end
			end
			assert.equals(2, count)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("configurable cell marker", function()
		after_each(function()
			cell_engine.configure({ cell_marker = "# %%" })
		end)

		it("should count cells with custom marker", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# COMMAND ----------",
				"x = 1",
				"# COMMAND ----------",
				"y = 2",
			})

			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			local count = cell_engine.count_cells(bufnr)
			assert.equals(2, count)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should find positions with custom marker", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# COMMAND ----------",
				"x = 1",
				"# COMMAND ----------",
				"y = 2",
			})

			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			local positions = cell_engine.get_cell_positions(bufnr)
			assert.same({ 1, 3 }, positions)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should not find standard markers when custom is set", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
			})

			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			local count = cell_engine.count_cells(bufnr)
			assert.equals(0, count)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("cell_engine module structure", function()
		it("should not have inline require for pyworks.ui inside functions", function()
			local source_path = "lua/pyworks/core/cell_engine.lua"
			local lines = vim.fn.readfile(source_path)

			local in_function = false
			local inline_count = 0
			for _, line in ipairs(lines) do
				if line:match("^function ") or line:match("^local function ") then
					in_function = true
				end
				if in_function and line:match('require%("pyworks%.ui"%)') then
					inline_count = inline_count + 1
				end
			end

			assert.are.equal(
				0,
				inline_count,
				"cell_engine.lua should not have inline require for pyworks.ui in functions"
			)
		end)
	end)

	describe("user commands", function()
		before_each(function()
			pcall(function()
				require("pyworks").setup()
			end)
		end)

		it("should register PyworksNextCell command", function()
			assert.equals(2, vim.fn.exists(":PyworksNextCell"))
		end)

		it("should register PyworksInsertCellBelow command", function()
			assert.equals(2, vim.fn.exists(":PyworksInsertCellBelow"))
		end)

		it("should register PyworksToggleCellType command", function()
			assert.equals(2, vim.fn.exists(":PyworksToggleCellType"))
		end)

		it("should register PyworksSplitCell command", function()
			assert.equals(2, vim.fn.exists(":PyworksSplitCell"))
		end)

		it("should register PyworksRunCell command", function()
			assert.equals(2, vim.fn.exists(":PyworksRunCell"))
		end)

		it("should register PyworksRunCellAdvance command", function()
			assert.equals(2, vim.fn.exists(":PyworksRunCellAdvance"))
		end)
	end)

	describe("run_cell", function()
		local ui
		-- C1 moves the kernel-readiness gate into run_cell itself, so these
		-- tests declare a ready kernel; the gate's own behaviour is covered below
		local function mark_ready()
			vim.b[vim.api.nvim_get_current_buf()].pyworks_kernel_ready = true
		end
		local original_mark_executed
		local original_get_cell_num
		local original_enter_cell
		local original_notify
		local original_defer_fn
		local notify_calls
		local mark_executed_calls
		local enter_cell_calls
		local deferred_callbacks
		local molten_eval_calls

		before_each(function()
			ui = require("pyworks.ui")
			mark_ready()
			notify_calls = {}
			mark_executed_calls = {}
			enter_cell_calls = {}
			deferred_callbacks = {}
			molten_eval_calls = {}

			original_mark_executed = ui.mark_cell_executed
			original_get_cell_num = ui.get_current_cell_number
			original_enter_cell = ui.enter_cell
			original_notify = vim.notify
			original_defer_fn = vim.defer_fn

			ui.get_current_cell_number = function()
				return 1
			end
			ui.mark_cell_executed = function(cell_num)
				table.insert(mark_executed_calls, cell_num)
			end
			ui.enter_cell = function(line, opts)
				table.insert(enter_cell_calls, { line = line, opts = opts })
			end
			vim.notify = function(msg, level)
				table.insert(notify_calls, { msg = msg, level = level })
			end
			vim.defer_fn = function(fn, _ms)
				table.insert(deferred_callbacks, fn)
			end

			-- Mock Molten's evaluate function via a real Vimscript user function
			-- so pcall(vim.fn.MoltenEvaluateRange, ...) records the call.
			vim.cmd([[
				let g:_test_molten_eval_calls = []
				function! MoltenEvaluateRange(start_line, end_line) abort
					call add(g:_test_molten_eval_calls, [a:start_line, a:end_line])
				endfunction
			]])
		end)

		after_each(function()
			ui.mark_cell_executed = original_mark_executed
			ui.get_current_cell_number = original_get_cell_num
			ui.enter_cell = original_enter_cell
			vim.notify = original_notify
			vim.defer_fn = original_defer_fn
			pcall(vim.cmd, "delfunction MoltenEvaluateRange")
			vim.g._test_molten_eval_calls = nil
		end)

		it("warns and returns false when no kernel is initialized", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "# %%", "x = 1" })
			vim.b[bufnr].molten_initialized = nil
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local ok = cell_engine.run_cell()
			assert.is_false(ok)
			assert.equals(0, #mark_executed_calls)

			local found_warn = false
			for _, n in ipairs(notify_calls) do
				if n.msg and n.msg:match("kernel") then
					found_warn = true
				end
			end
			assert.is_true(found_warn)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("returns false on an empty cell", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "# %%", "# %%" })
			vim.b[bufnr].molten_initialized = true
			vim.b[bufnr].pyworks_kernel_ready = true
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			local ok = cell_engine.run_cell()
			assert.is_false(ok)
			assert.equals(0, #mark_executed_calls)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("evaluates the current cell range and marks it executed", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"y = 2",
				"# %%",
				"z = 3",
			})
			vim.b[bufnr].molten_initialized = true
			vim.b[bufnr].pyworks_kernel_ready = true
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local ok = cell_engine.run_cell()
			assert.is_true(ok)
			assert.equals(1, #mark_executed_calls)

			local calls = vim.g._test_molten_eval_calls or {}
			assert.equals(1, #calls)
			assert.equals(2, calls[1][1])
			assert.equals(3, calls[1][2])

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("with advance=true defers cursor move to the next cell", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"# %%",
				"y = 2",
			})
			vim.b[bufnr].molten_initialized = true
			vim.b[bufnr].pyworks_kernel_ready = true
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local ok = cell_engine.run_cell({ advance = true })
			assert.is_true(ok)
			assert.equals(1, #deferred_callbacks)

			deferred_callbacks[1]()
			assert.equals(1, #enter_cell_calls)
			assert.equals(3, enter_cell_calls[1].line)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("without advance does not move the cursor", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"# %%",
				"y = 2",
			})
			vim.b[bufnr].molten_initialized = true
			vim.b[bufnr].pyworks_kernel_ready = true
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local ok = cell_engine.run_cell()
			assert.is_true(ok)
			assert.equals(0, #deferred_callbacks)
			assert.equals(0, #enter_cell_calls)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("notifies 'Last cell' when advancing past the final cell", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
			})
			vim.b[bufnr].molten_initialized = true
			vim.b[bufnr].pyworks_kernel_ready = true
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local ok = cell_engine.run_cell({ advance = true })
			assert.is_true(ok)
			assert.equals(1, #deferred_callbacks)

			deferred_callbacks[1]()
			assert.equals(0, #enter_cell_calls)

			local found_last = false
			for _, n in ipairs(notify_calls) do
				if n.msg and n.msg:match("Last cell") then
					found_last = true
				end
			end
			assert.is_true(found_last)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	-- =========================================================================
	-- Custom cell_marker configuration (Issue #5 — Databricks support)
	-- =========================================================================

	-- C1: the gate added in 62c4d12 lived in keymaps.lua, so :PyworksRunCell and
	-- :PyworksRunCellAdvance bypassed it - and those commands exist for
	-- skip_keymaps users (issue #4), i.e. the people who opted out of our
	-- keymaps were the ones still losing cells to the IOPub flush.
	describe("run_cell kernel readiness gate", function()
		local kernel_ready

		before_each(function()
			package.loaded["pyworks.core.kernel_ready"] = nil
			kernel_ready = require("pyworks.core.kernel_ready")
			kernel_ready._reset()
			kernel_ready.setup()

			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# %%", "print(1)" })
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			local buf = vim.api.nvim_get_current_buf()
			vim.b[buf].molten_initialized = true
			vim.b[buf].pyworks_kernel_ready = true
			vim.b[buf].pyworks_kernel_name = "gate_kernel"
			vim.b[buf].pyworks_kernel_ready = nil
		end)

		it("should not evaluate while the kernel is still starting", function()
			local evaluated = false
			local original = vim.fn.MoltenEvaluateRange
			vim.fn.MoltenEvaluateRange = function()
				evaluated = true
			end

			cell_engine.run_cell()
			vim.wait(150, function()
				return evaluated
			end, 25)

			vim.fn.MoltenEvaluateRange = original
			assert.is_false(evaluated)
		end)

		it("should evaluate once the kernel reports ready", function()
			local evaluated = false
			local original = vim.fn.MoltenEvaluateRange
			vim.fn.MoltenEvaluateRange = function()
				evaluated = true
			end

			cell_engine.run_cell()
			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "gate_kernel" },
			})
			vim.wait(1000, function()
				return evaluated
			end, 25)

			vim.fn.MoltenEvaluateRange = original
			assert.is_true(evaluated)
		end)
	end)

	describe("custom cell_marker", function()
		before_each(function()
			package.loaded["pyworks.core.cell_engine"] = nil
			cell_engine = require("pyworks.core.cell_engine")
		end)

		it("defaults to # %%", function()
			local pat = cell_engine.get_cell_pattern()
			local vpat = cell_engine.vim_search_pattern()
			assert.is_not_nil(pat:find("# "))
			assert.equals("^# %%", vpat)
		end)

		it("configure changes the cell marker", function()
			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			assert.matches("COMMAND", cell_engine.vim_search_pattern())
			assert.matches("COMMAND", cell_engine.get_cell_pattern())
		end)

		it("vim_search_pattern returns raw marker for vim.fn.search", function()
			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			assert.equals("^# COMMAND ----------", cell_engine.vim_search_pattern())
		end)

		it("get_cell_pattern escapes Lua pattern special chars", function()
			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			local pat = cell_engine.get_cell_pattern()
			-- Dashes should be escaped as %-
			assert.matches("%%%-", pat)
		end)

		it("find_cell_boundaries works with custom marker", function()
			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# COMMAND ----------",
				"x = 1",
				"y = 2",
				"# COMMAND ----------",
				"z = 3",
			})

			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			local start_line, end_line = cell_engine.find_cell_boundaries()
			assert.equals(2, start_line)
			assert.equals(3, end_line)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("count_cells works with custom marker", function()
			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# COMMAND ----------",
				"x = 1",
				"# COMMAND ----------",
				"y = 2",
			})

			local count = cell_engine.count_cells(bufnr)
			assert.equals(2, count)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("does NOT match default # %% when custom marker is set", function()
			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# %%",
				"x = 1",
				"# COMMAND ----------",
				"y = 2",
			})

			-- Should find only 1 cell (the COMMAND marker), not the # %% line
			local count = cell_engine.count_cells(bufnr)
			assert.equals(1, count)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("insert_cell_below uses the configured marker", function()
			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# COMMAND ----------",
				"x = 1",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			cell_engine.insert_cell_below()

			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local found_command = false
			local found_default = false
			for _, line in ipairs(lines) do
				if line == "# COMMAND ----------" then
					found_command = true
				end
				if line == "# %%" then
					found_default = true
				end
			end
			-- The new cell should use COMMAND marker, not # %%
			assert.is_true(found_command)
			assert.is_false(found_default)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("navigation works with custom marker", function()
			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"# COMMAND ----------",
				"x = 1",
				"# COMMAND ----------",
				"y = 2",
			})
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			local found = cell_engine.next_cell()
			assert.is_true(found)
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(4, cursor[1])

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)
end)
