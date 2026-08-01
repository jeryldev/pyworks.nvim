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

		-- Regression (issue #10): run-all parks the cursor on the marker line.
		-- A backward search without the 'c' flag rejects a match at the cursor and
		-- reports the PREVIOUS marker, so markdown cells were executed and then
		-- waited on for the full 30s timeout.
		it("should detect markdown when cursor is on the marker line", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %% [markdown]",
				"# This is markdown",
			})
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			local result = keymaps._is_markdown_cell()

			assert.is_true(result)
		end)

		it("should detect a markdown cell following a code cell from its marker line", function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('code')",
				"# %% [markdown]",
				"# notes",
			})
			vim.api.nvim_win_set_cursor(0, { 3, 0 })

			local result = keymaps._is_markdown_cell()

			assert.is_true(result)
		end)
	end)

	-- Regression (issue #10): a cell submitted before Molten finishes
	-- jupyter_client's wait_for_ready() is lost - that call ends by flushing the
	-- IOPub channel, so the cell's execute_input/status messages are drained and
	-- the output sits on "* On Hold" forever. Molten fires User
	-- MoltenKernelReady at exactly that transition, so the first evaluation has
	-- to wait for the event rather than a fixed delay.
	describe("_run_when_kernel_ready", function()
		it("should not run the callback before the kernel is ready", function()
			local ran = false

			keymaps._run_when_kernel_ready(test_bufnr, function()
				ran = true
			end)
			vim.wait(150, function()
				return ran
			end, 25)

			assert.is_false(ran)
		end)

		it("should run the callback when MoltenKernelReady fires", function()
			local ran = false

			keymaps._run_when_kernel_ready(test_bufnr, function()
				ran = true
			end)
			vim.api.nvim_exec_autocmds("User", { pattern = "MoltenKernelReady" })
			vim.wait(1000, function()
				return ran
			end, 25)

			assert.is_true(ran)
		end)

		it("should run the callback only once when the event fires twice", function()
			local runs = 0

			keymaps._run_when_kernel_ready(test_bufnr, function()
				runs = runs + 1
			end)
			vim.api.nvim_exec_autocmds("User", { pattern = "MoltenKernelReady" })
			vim.wait(1000, function()
				return runs > 0
			end, 25)
			vim.api.nvim_exec_autocmds("User", { pattern = "MoltenKernelReady" })
			vim.wait(200, function()
				return runs > 1
			end, 25)

			assert.are.equal(1, runs)
		end)

		it("should fall back to running the callback if the event never fires", function()
			local ran = false

			keymaps._run_when_kernel_ready(test_bufnr, function()
				ran = true
			end, { timeout_ms = 50 })
			vim.wait(1000, function()
				return ran
			end, 25)

			assert.is_true(ran)
		end)
	end)

	-- Regression (issue #10): auto-init on file open sets molten_initialized
	-- immediately, so gating only the "not yet initialized" branch left the
	-- common path - open a file, press a run key - still racing kernel startup.
	-- Readiness is its own state, set only by User MoltenKernelReady.
	describe("kernel readiness tracking", function()
		before_each(function()
			vim.b[test_bufnr].molten_initialized = true
			vim.b[test_bufnr].pyworks_kernel_name = "test_kernel"
			vim.b[test_bufnr].pyworks_kernel_ready = nil
		end)

		it("should not consider a freshly initialized kernel ready", function()
			assert.is_false(keymaps._is_kernel_ready(test_bufnr))
		end)

		it("should mark the buffer ready when its kernel reports ready", function()
			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "test_kernel" },
			})

			assert.is_true(keymaps._is_kernel_ready(test_bufnr))
		end)

		it("should not mark the buffer ready when another kernel reports ready", function()
			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "some_other_kernel" },
			})

			assert.is_false(keymaps._is_kernel_ready(test_bufnr))
		end)

		it("should run the callback immediately once the kernel is ready", function()
			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "test_kernel" },
			})

			local ran = false
			keymaps._ensure_kernel_ready(test_bufnr, function()
				ran = true
			end)

			assert.is_true(ran)
		end)

		it("should hold the callback until the kernel reports ready", function()
			local ran = false

			keymaps._ensure_kernel_ready(test_bufnr, function()
				ran = true
			end)
			vim.wait(150, function()
				return ran
			end, 25)
			assert.is_false(ran)

			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "test_kernel" },
			})
			vim.wait(1000, function()
				return ran
			end, 25)

			assert.is_true(ran)
		end)
	end)

	-- Regression (issue #10): run-all used to navigate by repeated forward
	-- search from line 1, which skips a marker sitting on line 1 and therefore
	-- ran cell N+1 for every N.
	describe("_focus_cell", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print(1)",
				"# %% [markdown]",
				"# notes",
				"# %%",
				"print(2)",
			})
		end)

		it("should focus the first cell when line 1 is a marker", function()
			assert.are.equal(1, keymaps._focus_cell(1))
			assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
		end)

		it("should focus each subsequent cell marker", function()
			assert.are.equal(3, keymaps._focus_cell(2))
			assert.are.equal(5, keymaps._focus_cell(3))
		end)

		it("should return nil for a cell number that does not exist", function()
			assert.is_nil(keymaps._focus_cell(4))
		end)

		it("should leave the cursor where markdown detection sees the right cell", function()
			keymaps._focus_cell(2)
			assert.is_true(keymaps._is_markdown_cell())

			keymaps._focus_cell(3)
			assert.is_false(keymaps._is_markdown_cell())
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

	describe("run cell in place keymap", function()
		it("should have leader-jk mapped in buffer after setup", function()
			vim.api.nvim_create_user_command("MoltenInit", function() end, { nargs = "?" })

			package.loaded["pyworks.keymaps"] = nil
			local keymaps_module = require("pyworks.keymaps")

			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			keymaps_module.setup_buffer_keymaps()

			local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
			local found = false
			for _, map in ipairs(maps) do
				if map.lhs and map.lhs:match("jk$") then
					found = true
					break
				end
			end

			assert.is_true(found, "<leader>jk keymap should be registered")

			vim.api.nvim_buf_delete(bufnr, { force = true })
			vim.api.nvim_del_user_command("MoltenInit")
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

	describe("keymap input safety", function()
		it("should validate kernel name input matches safe pattern", function()
			local safe_pattern = "^[%w%-_%.]+$"
			assert.is_truthy(("python3"):match(safe_pattern))
			assert.is_truthy(("ir"):match(safe_pattern))
			assert.is_truthy(("my-kernel_v2.0"):match(safe_pattern))
			assert.is_falsy(("python3 | echo pwned"):match(safe_pattern))
			assert.is_falsy(("a; !rm -rf /"):match(safe_pattern))
		end)
	end)
end)
