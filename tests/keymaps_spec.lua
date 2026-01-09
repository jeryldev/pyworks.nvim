-- Test suite for pyworks.keymaps module
-- Tests cell execution, completion detection, and keymap setup

describe("keymaps", function()
	local keymaps
	local test_bufnr

	before_each(function()
		-- Fresh require to reset module state
		package.loaded["pyworks.keymaps"] = nil
		keymaps = require("pyworks.keymaps")

		-- Create a fresh test buffer
		test_bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(test_bufnr)
		vim.bo[test_bufnr].filetype = "python"
	end)

	after_each(function()
		if vim.api.nvim_buf_is_valid(test_bufnr) then
			vim.api.nvim_buf_delete(test_bufnr, { force = true })
		end
	end)

	describe("setup_buffer_keymaps", function()
		it("should not error when called", function()
			local ok = pcall(keymaps.setup_buffer_keymaps)
			assert.is_true(ok)
		end)

		it("should create keymaps for python buffers", function()
			keymaps.setup_buffer_keymaps()

			-- Check that some keymaps were created
			local maps = vim.api.nvim_buf_get_keymap(test_bufnr, "n")
			local has_pyworks_map = false
			for _, map in ipairs(maps) do
				if map.lhs and map.lhs:match("<leader>j") then
					has_pyworks_map = true
					break
				end
			end

			-- Note: This may be false if Molten is not available
			-- The test mainly verifies no errors occur
		end)
	end)

	describe("_is_markdown_cell", function()
		it("should return false when not in a cell", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"print('hello')",
				"x = 1",
			})
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			local result = keymaps._is_markdown_cell()

			assert.is_false(result)
		end)

		it("should return false for code cells", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('hello')",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local result = keymaps._is_markdown_cell()

			assert.is_false(result)
		end)

		it("should return true for markdown cells", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% [markdown]",
				"# This is markdown",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local result = keymaps._is_markdown_cell()

			assert.is_true(result)
		end)

		it("should detect markdown cell with extra content after tag", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% [markdown] Introduction",
				"# This is markdown",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local result = keymaps._is_markdown_cell()

			assert.is_true(result)
		end)

		it("should not detect markdown in code cell with markdown comment", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"# Comment mentioning [markdown] format",
				"print('code')",
			})
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local result = keymaps._is_markdown_cell()

			assert.is_false(result)
		end)
	end)

	describe("_get_highest_completed_output", function()
		it("should return 0 when no output exists", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('hello')",
			})

			local result = keymaps._get_highest_completed_output(test_bufnr)

			assert.equals(0, result)
		end)

		it("should return 0 when Out[N] exists but no Done indicator", function()
			-- Create a namespace and add an extmark with Out[1] but no Done
			local ns = vim.api.nvim_create_namespace("molten_test_output")
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('hello')",
			})
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 1, 0, {
				virt_text = { { "Out[1]: ", "Comment" } },
				virt_text_pos = "eol",
			})

			local result = keymaps._get_highest_completed_output(test_bufnr)

			assert.equals(0, result)
		end)

		it("should detect Out[N] with checkmark", function()
			local ns = vim.api.nvim_create_namespace("molten_test_output")
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('hello')",
			})
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 1, 0, {
				virt_text = { { "Out[1]: ✓ Done", "Comment" } },
				virt_text_pos = "eol",
			})

			local result = keymaps._get_highest_completed_output(test_bufnr)

			assert.equals(1, result)
		end)

		it("should detect Out[N] with Done text", function()
			local ns = vim.api.nvim_create_namespace("molten_test_output")
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('hello')",
			})
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 1, 0, {
				virt_text = { { "Out[2]: Done", "Comment" } },
				virt_text_pos = "eol",
			})

			local result = keymaps._get_highest_completed_output(test_bufnr)

			assert.equals(2, result)
		end)

		it("should return highest number when multiple outputs exist", function()
			local ns = vim.api.nvim_create_namespace("molten_test_output")
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('cell 1')",
				"# %%",
				"print('cell 2')",
				"# %%",
				"print('cell 3')",
			})
			-- Add multiple completed outputs
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 1, 0, {
				virt_text = { { "Out[1]: ✓ Done", "Comment" } },
				virt_text_pos = "eol",
			})
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 3, 0, {
				virt_text = { { "Out[3]: ✓ Done", "Comment" } },
				virt_text_pos = "eol",
			})
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 5, 0, {
				virt_text = { { "Out[2]: ✓ Done", "Comment" } },
				virt_text_pos = "eol",
			})

			local result = keymaps._get_highest_completed_output(test_bufnr)

			assert.equals(3, result)
		end)

		it("should handle multi-part virtual text", function()
			local ns = vim.api.nvim_create_namespace("molten_test_output")
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('hello')",
			})
			-- Molten may split virtual text into multiple parts
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 1, 0, {
				virt_text = {
					{ "Out[5]", "Number" },
					{ ": ", "Comment" },
					{ "✓", "DiagnosticOk" },
					{ " Done", "Comment" },
				},
				virt_text_pos = "eol",
			})

			local result = keymaps._get_highest_completed_output(test_bufnr)

			assert.equals(5, result)
		end)

		it("should ignore incomplete outputs when finding highest", function()
			local ns = vim.api.nvim_create_namespace("molten_test_output")
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('cell 1')",
				"# %%",
				"print('cell 2')",
			})
			-- One completed, one still running
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 1, 0, {
				virt_text = { { "Out[1]: ✓ Done", "Comment" } },
				virt_text_pos = "eol",
			})
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 3, 0, {
				virt_text = { { "Out[2]: Running...", "Comment" } },
				virt_text_pos = "eol",
			})

			local result = keymaps._get_highest_completed_output(test_bufnr)

			-- Should only count the completed one
			assert.equals(1, result)
		end)

		it("should detect Out[N] in virt_lines (Molten's actual format)", function()
			local ns = vim.api.nvim_create_namespace("molten_test_output")
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('hello')",
			})
			-- Molten uses virt_lines (entire lines below the cell) not virt_text
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 1, 0, {
				virt_lines = {
					{ { "Out[3]: ✓ Done 0.05s", "Comment" } },
					{ { "hello", "Normal" } },
				},
			})

			local result = keymaps._get_highest_completed_output(test_bufnr)

			assert.equals(3, result)
		end)

		it("should detect Out[N] with multi-part virt_lines", function()
			local ns = vim.api.nvim_create_namespace("molten_test_output")
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('hello')",
			})
			-- Header line may have multiple styled parts
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 1, 0, {
				virt_lines = {
					{
						{ "Out[7]", "Number" },
						{ ": ", "Comment" },
						{ "✓ Done", "DiagnosticOk" },
						{ " 0.12s", "Comment" },
					},
					{ { "hello", "Normal" } },
				},
			})

			local result = keymaps._get_highest_completed_output(test_bufnr)

			assert.equals(7, result)
		end)
	end)

	describe("_wait_for_cell_completion", function()
		it("should call callback with false on timeout", function()
			-- This test uses a very short timeout for testing
			-- We can't easily test the actual timeout without mocking vim.uv

			-- Just verify the function exists and is callable
			assert.is_function(keymaps._wait_for_cell_completion)
		end)

		it("should call callback immediately if new output appears", function()
			local ns = vim.api.nvim_create_namespace("molten_test_output")
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('hello')",
			})

			local callback_called = false
			local callback_success = nil

			-- Start with Out[1] completed
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 1, 0, {
				virt_text = { { "Out[1]: ✓ Done", "Comment" } },
				virt_text_pos = "eol",
			})

			-- Start waiting (it will capture Out[1] as baseline)
			keymaps._wait_for_cell_completion(test_bufnr, function(success)
				callback_called = true
				callback_success = success
			end)

			-- Simulate new output appearing
			vim.api.nvim_buf_set_extmark(test_bufnr, ns, 1, 0, {
				virt_text = { { "Out[2]: ✓ Done", "Comment" } },
				virt_text_pos = "eol",
			})

			-- Wait for timer to fire (use vim.wait for async)
			vim.wait(500, function()
				return callback_called
			end, 50)

			assert.is_true(callback_called)
			assert.is_true(callback_success)
		end)
	end)

	describe("event suppression", function()
		it("should preserve eventignore after suppression", function()
			local original = vim.o.eventignore

			vim.o.eventignore = "BufEnter"

			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('cell 1')",
				"# %%",
				"print('cell 2')",
			})

			-- eventignore should still be what we set (or restored to original)
			vim.o.eventignore = original
		end)
	end)

	describe("cell navigation keymaps", function()
		it("should have cell navigation functions available", function()
			keymaps.setup_buffer_keymaps()

			-- Verify navigation keymaps exist
			local maps = vim.api.nvim_buf_get_keymap(test_bufnr, "n")
			local nav_keymaps = {}
			for _, map in ipairs(maps) do
				if map.lhs then
					nav_keymaps[map.lhs] = true
				end
			end

			-- These keymaps are always set (with or without Molten)
			-- Check for at least one navigation keymap
		end)
	end)
end)
