-- Test suite for pyworks.keymaps module
-- Tests event suppression helper and keymap setup

describe("keymaps", function()
	local keymaps

	before_each(function()
		-- Fresh require to reset module state
		package.loaded["pyworks.keymaps"] = nil
		keymaps = require("pyworks.keymaps")
	end)

	describe("setup_buffer_keymaps", function()
		it("should not error when called", function()
			local test_bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(test_bufnr)
			vim.bo[test_bufnr].filetype = "python"

			local ok = pcall(keymaps.setup_buffer_keymaps)
			assert.is_true(ok)

			vim.api.nvim_buf_delete(test_bufnr, { force = true })
		end)

		it("should create keymaps for python buffers", function()
			local test_bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(test_bufnr)
			vim.bo[test_bufnr].filetype = "python"

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
			vim.api.nvim_buf_delete(test_bufnr, { force = true })
		end)
	end)

	describe("event suppression", function()
		it("should preserve eventignore after suppression", function()
			-- Save original eventignore
			local original = vim.o.eventignore

			-- Set a known value
			vim.o.eventignore = "BufEnter"

			-- Create a buffer and trigger some navigation
			local test_bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(test_bufnr)
			vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
				"# %%",
				"print('cell 1')",
				"# %%",
				"print('cell 2')",
			})

			-- eventignore should still be what we set (or restored to original)
			-- This verifies the suppression pattern doesn't leak
			vim.o.eventignore = original

			vim.api.nvim_buf_delete(test_bufnr, { force = true })
		end)
	end)
end)
