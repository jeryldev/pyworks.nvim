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
	end)

	-- =========================================================================
	-- Custom cell_marker configuration (Issue #5 — Databricks support)
	-- =========================================================================

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
