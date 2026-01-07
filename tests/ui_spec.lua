-- Test suite for pyworks.ui module
-- Tests cell highlighting, numbering, and execution tracking

local ui = require("pyworks.ui")

describe("ui", function()
	local test_bufnr

	before_each(function()
		-- Create a fresh test buffer before each test
		test_bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(test_bufnr)
		-- Reset executed cells tracking
		ui.executed_cells = {}
	end)

	after_each(function()
		-- Clean up test buffer
		if vim.api.nvim_buf_is_valid(test_bufnr) then
			vim.api.nvim_buf_delete(test_bufnr, { force = true })
		end
	end)

	describe("setup_cell_highlights", function()
		it("should create highlight groups for dark mode", function()
			vim.o.background = "dark"
			ui.setup_cell_highlights()

			local unrun_hl = vim.api.nvim_get_hl(0, { name = "PyworksCellNumberUnrun" })
			local executed_hl = vim.api.nvim_get_hl(0, { name = "PyworksCellNumberExecuted" })

			assert.is_not_nil(unrun_hl.fg)
			assert.is_not_nil(executed_hl.fg)
			assert.is_true(unrun_hl.bold)
			assert.is_true(executed_hl.bold)
		end)

		it("should create highlight groups for light mode", function()
			vim.o.background = "light"
			ui.setup_cell_highlights()

			local unrun_hl = vim.api.nvim_get_hl(0, { name = "PyworksCellNumberUnrun" })
			local executed_hl = vim.api.nvim_get_hl(0, { name = "PyworksCellNumberExecuted" })

			assert.is_not_nil(unrun_hl.fg)
			assert.is_not_nil(executed_hl.fg)
		end)
	end)

	describe("mark_cell_executed", function()
		it("should track executed cells for buffer", function()
			ui.mark_cell_executed(1)
			ui.mark_cell_executed(3)

			assert.is_true(ui.executed_cells[test_bufnr][1])
			assert.is_nil(ui.executed_cells[test_bufnr][2])
			assert.is_true(ui.executed_cells[test_bufnr][3])
		end)

		it("should initialize buffer tracking if not exists", function()
			assert.is_nil(ui.executed_cells[test_bufnr])

			ui.mark_cell_executed(1)

			assert.is_not_nil(ui.executed_cells[test_bufnr])
			assert.is_true(ui.executed_cells[test_bufnr][1])
		end)
	end)

	describe("get_current_cell_number", function()
		it("should return 0 when no cells in buffer", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"print('hello')",
				"x = 1",
			})
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			local cell_num = ui.get_current_cell_number()

			assert.equals(0, cell_num)
		end)

		it("should return correct cell number at cursor position", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% Cell 1",
				"print('cell 1')",
				"# %% Cell 2",
				"print('cell 2')",
				"# %% Cell 3",
				"print('cell 3')",
			})

			-- Position cursor in cell 1
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			assert.equals(1, ui.get_current_cell_number())

			-- Position cursor in cell 2
			vim.api.nvim_win_set_cursor(0, { 4, 0 })
			assert.equals(2, ui.get_current_cell_number())

			-- Position cursor in cell 3
			vim.api.nvim_win_set_cursor(0, { 6, 0 })
			assert.equals(3, ui.get_current_cell_number())
		end)

		it("should count cell at cursor line", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% Cell 1",
				"# %% Cell 2",
			})

			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			assert.equals(2, ui.get_current_cell_number())
		end)
	end)

	describe("number_cells", function()
		it("should add virtual text to cell markers", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% Cell 1",
				"print('hello')",
				"# %% Cell 2",
			})

			ui.number_cells()

			-- Check that extmarks were created in pyworks namespace
			local ns = vim.api.nvim_create_namespace("pyworks_cell_numbers")
			local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})

			assert.equals(2, #marks)
		end)

		it("should identify markdown cells", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% [markdown]",
				"# This is markdown",
				"# %% code cell",
			})

			ui.number_cells()

			local ns = vim.api.nvim_create_namespace("pyworks_cell_numbers")
			local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })

			assert.equals(2, #marks)
		end)

		it("should not add marks to non-cell lines", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# regular comment",
				"print('hello')",
				"# another comment",
			})

			ui.number_cells()

			local ns = vim.api.nvim_create_namespace("pyworks_cell_numbers")
			local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})

			assert.equals(0, #marks)
		end)
	end)

	describe("cell_fold_expr", function()
		it("should return fold level for cell markers", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% Cell 1",
				"print('hello')",
				"# %% Cell 2",
			})

			-- Cell marker should start a new fold (vim.v.lnum is set by fold system)
			vim.v.lnum = 1
			local fold_level = ui.cell_fold_expr()
			assert.equals(">1", fold_level)

			-- Non-cell line should continue fold
			vim.v.lnum = 2
			fold_level = ui.cell_fold_expr()
			assert.equals("=", fold_level)

			-- Another cell marker
			vim.v.lnum = 3
			fold_level = ui.cell_fold_expr()
			assert.equals(">1", fold_level)
		end)
	end)

	describe("find_first_cell", function()
		it("should return line number of first cell marker", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% Cell 1",
				"print('hello')",
				"# %% Cell 2",
			})

			local line = ui.find_first_cell()

			assert.equals(1, line)
		end)

		it("should return nil when no cell markers exist", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"print('hello')",
				"x = 1",
			})

			local line = ui.find_first_cell()

			assert.is_nil(line)
		end)

		it("should not move cursor", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"print('hello')",
				"# %% Cell 1",
				"x = 1",
			})
			vim.api.nvim_win_set_cursor(0, { 3, 0 })

			ui.find_first_cell()

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(3, cursor[1])
		end)

		it("should find cell even if not on first line", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# Header comment",
				"import os",
				"# %% Cell 1",
				"print('hello')",
			})

			local line = ui.find_first_cell()

			assert.equals(3, line)
		end)
	end)

	describe("enter_cell", function()
		it("should position cursor below marker line", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% Cell 1",
				"print('hello')",
				"# %% Cell 2",
			})

			ui.enter_cell(1)

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(2, cursor[1])
		end)

		it("should add empty line if marker is at end of file", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% Cell 1",
			})

			ui.enter_cell(1)

			local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
			assert.equals(2, #lines)
			assert.equals("", lines[2])
		end)
	end)

	describe("enter_first_cell", function()
		it("should position cursor below first cell marker", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% Cell 1",
				"print('hello')",
			})

			ui.enter_first_cell()

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(2, cursor[1])
		end)

		it("should go to line 1 when no cell markers exist", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"print('hello')",
				"x = 1",
			})

			ui.enter_first_cell()

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(1, cursor[1])
		end)
	end)
end)
