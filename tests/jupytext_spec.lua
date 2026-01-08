-- Test suite for pyworks.notebook.jupytext module
-- Tests notebook handling, jupytext.nvim detection, and CLI integration

local jupytext = require("pyworks.notebook.jupytext")

describe("jupytext", function()
	describe("is_jupytext_installed", function()
		it("should return boolean", function()
			local result = jupytext.is_jupytext_installed()
			assert.is_boolean(result)
		end)

		it("should check PATH for jupytext executable", function()
			-- This test verifies the function doesn't error
			-- Actual result depends on system state
			local ok, result = pcall(jupytext.is_jupytext_installed)
			assert.is_true(ok)
			assert.is_boolean(result)
		end)
	end)

	describe("find_jupytext_cli", function()
		it("should return string or nil", function()
			local result = jupytext.find_jupytext_cli()
			if result then
				assert.is_string(result)
			else
				assert.is_nil(result)
			end
		end)
	end)

	describe("get_python_for_jupytext", function()
		it("should return a python path", function()
			local result = jupytext.get_python_for_jupytext()
			assert.is_string(result)
			-- Should end with python or python3
			assert.is_true(result:match("python") ~= nil)
		end)

		it("should handle nil filepath", function()
			local ok, result = pcall(jupytext.get_python_for_jupytext, nil)
			assert.is_true(ok)
			assert.is_string(result)
		end)
	end)

	describe("configure_notebook_handler", function()
		it("should return boolean indicating success", function()
			local result = jupytext.configure_notebook_handler()
			assert.is_boolean(result)
		end)

		it("should set up BufReadCmd autocmd for .ipynb files", function()
			jupytext.configure_notebook_handler()

			-- Check that autocmd was created
			local autocmds = vim.api.nvim_get_autocmds({
				group = "PyworksNotebook",
				event = "BufReadCmd",
				pattern = "*.ipynb",
			})
			assert.is_true(#autocmds > 0)
		end)

		it("should set up BufWriteCmd autocmd for .ipynb files", function()
			jupytext.configure_notebook_handler()

			-- Check that autocmd was created
			local autocmds = vim.api.nvim_get_autocmds({
				group = "PyworksNotebook",
				event = "BufWriteCmd",
				pattern = "*.ipynb",
			})
			assert.is_true(#autocmds > 0)
		end)
	end)

	describe("setup_notebook_handler", function()
		it("should create PyworksNotebook augroup", function()
			jupytext.setup_notebook_handler()

			-- Verify augroup exists by trying to get autocmds from it
			local ok = pcall(vim.api.nvim_get_autocmds, { group = "PyworksNotebook" })
			assert.is_true(ok)
		end)

		it("should clear existing autocmds before creating new ones", function()
			-- Call twice to ensure no duplicate autocmds
			jupytext.setup_notebook_handler()
			jupytext.setup_notebook_handler()

			local autocmds = vim.api.nvim_get_autocmds({
				group = "PyworksNotebook",
				event = "BufReadCmd",
				pattern = "*.ipynb",
			})
			-- Should only have one autocmd, not two
			assert.equals(1, #autocmds)
		end)
	end)

	describe("reload_notebook", function()
		it("should return false for non-notebook files", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(bufnr, "/tmp/test.py")
			vim.api.nvim_set_current_buf(bufnr)

			local result = jupytext.reload_notebook(bufnr)
			assert.is_false(result)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)
end)
