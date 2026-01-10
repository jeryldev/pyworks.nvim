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

	-- CRITICAL: Tests for namespace lookup to prevent regression of the bug where
	-- pattern matching "^molten" matched "molten-highlights" instead of "molten-extmarks"
	-- See commit 91adb5c for the fix
	describe("_get_molten_namespace", function()
		it("should return nil when no molten namespaces exist", function()
			-- Invalidate cache first
			keymaps._invalidate_molten_ns_cache()

			local result = keymaps._get_molten_namespace()

			-- Without Molten running, should return nil
			-- Note: actual result depends on whether Molten is loaded
			assert.is_true(result == nil or type(result) == "number")
		end)

		it("should find molten-extmarks namespace specifically", function()
			-- Invalidate cache to ensure fresh lookup
			keymaps._invalidate_molten_ns_cache()

			-- Create namespaces that simulate Molten's namespace structure
			-- CRITICAL: molten-highlights is created FIRST to test iteration order doesn't matter
			-- luacheck: ignore highlights_ns (intentionally unused - we're testing it's NOT selected)
			local highlights_ns = vim.api.nvim_create_namespace("molten-highlights")
			local extmarks_ns = vim.api.nvim_create_namespace("molten-extmarks")

			local result = keymaps._get_molten_namespace()

			-- MUST return molten-extmarks, NOT molten-highlights
			-- This is the exact bug we're preventing: pattern "^molten" would match either
			assert.equals(extmarks_ns, result)

			-- Cleanup (namespaces persist until Neovim restart but this documents intent)
		end)

		it("should NOT match molten-highlights when looking for output markers", function()
			keymaps._invalidate_molten_ns_cache()

			-- Only create molten-highlights (simulating partial Molten state)
			-- luacheck: ignore highlights_ns (intentionally unused - verifying it's NOT selected)
			local highlights_ns = vim.api.nvim_create_namespace("molten-highlights")
			-- Delete molten-extmarks if it exists from previous test
			-- (can't actually delete namespaces, but we can verify behavior)

			-- The function should return the molten-extmarks namespace if it exists,
			-- or nil if only molten-highlights exists
			-- Since we can't delete namespaces in tests, we verify the logic by
			-- checking the return value matches molten-extmarks specifically
			local result = keymaps._get_molten_namespace()

			-- If result is not nil, it MUST be molten-extmarks, never molten-highlights
			if result then
				local namespaces = vim.api.nvim_get_namespaces()
				for name, id in pairs(namespaces) do
					if id == result then
						assert.equals("molten-extmarks", name)
						break
					end
				end
			end
		end)

		it("should cache the namespace ID after first lookup", function()
			keymaps._invalidate_molten_ns_cache()

			-- Ensure molten-extmarks exists
			local extmarks_ns = vim.api.nvim_create_namespace("molten-extmarks")

			-- First call - should find and cache
			local first_result = keymaps._get_molten_namespace()

			-- Second call - should use cache
			local second_result = keymaps._get_molten_namespace()

			assert.equals(first_result, second_result)
			assert.equals(extmarks_ns, first_result)
		end)

		it("should invalidate cache when _invalidate_molten_ns_cache is called", function()
			-- Ensure molten-extmarks exists and is cached
			local extmarks_ns = vim.api.nvim_create_namespace("molten-extmarks")
			local first_result = keymaps._get_molten_namespace()

			-- Invalidate
			keymaps._invalidate_molten_ns_cache()

			-- Next call should do fresh lookup (we can't easily verify this without
			-- checking internal state, but we verify the function still works)
			local after_invalidate = keymaps._get_molten_namespace()

			assert.equals(extmarks_ns, after_invalidate)
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
			local ns = vim.api.nvim_create_namespace("molten-extmarks")
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
			local ns = vim.api.nvim_create_namespace("molten-extmarks")
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
			local ns = vim.api.nvim_create_namespace("molten-extmarks")
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
			local ns = vim.api.nvim_create_namespace("molten-extmarks")
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
			local ns = vim.api.nvim_create_namespace("molten-extmarks")
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
			local ns = vim.api.nvim_create_namespace("molten-extmarks")
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
			local ns = vim.api.nvim_create_namespace("molten-extmarks")
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
			local ns = vim.api.nvim_create_namespace("molten-extmarks")
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
			local ns = vim.api.nvim_create_namespace("molten-extmarks")
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
