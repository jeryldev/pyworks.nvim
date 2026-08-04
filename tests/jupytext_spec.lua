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

-- A1: the notebook writer used io.open(path, "w"), which truncates the user's
-- notebook before writing and discards the close() error, so a full disk
-- reported "Notebook saved" over a destroyed file.
describe("jupytext notebook validation", function()
	it("should accept a real notebook document", function()
		local content = vim.json.encode({ cells = {}, nbformat = 4, nbformat_minor = 5 })

		assert.is_true(jupytext._is_valid_notebook(content))
	end)

	it("should reject content that is not JSON", function()
		assert.is_false(jupytext._is_valid_notebook("# %%\nprint(1)"))
	end)

	it("should reject JSON without a cells array", function()
		assert.is_false(jupytext._is_valid_notebook(vim.json.encode({ metadata = {} })))
	end)

	it("should reject empty output", function()
		assert.is_false(jupytext._is_valid_notebook(""))
		assert.is_false(jupytext._is_valid_notebook(nil))
	end)
end)

-- E3: conversion cost 720-950 ms on every .ipynb open and again on every save,
-- against the project's target of <500 ms for notebook opening. Most of that is
-- interpreter startup, so a conversion is reused while the file is unchanged.
describe("jupytext conversion cache", function()
	local nb

	before_each(function()
		jupytext._clear_conversion_cache()
		nb = vim.fn.tempname() .. ".ipynb"
		vim.fn.writefile({ vim.json.encode({ cells = {}, nbformat = 4, nbformat_minor = 5 }) }, nb)
	end)

	after_each(function()
		vim.fn.delete(nb)
	end)

	it("should return the cached conversion for an unchanged file", function()
		jupytext._cache_conversion(nb, "# %%\nprint(1)")

		assert.are.equal("# %%\nprint(1)", jupytext._cached_conversion(nb))
	end)

	it("should miss for a file it has never seen", function()
		assert.is_nil(jupytext._cached_conversion(vim.fn.tempname() .. ".ipynb"))
	end)

	it("should invalidate when the file changes", function()
		jupytext._cache_conversion(nb, "# %%\nold")
		vim.fn.writefile({ vim.json.encode({ cells = { 1 }, nbformat = 4 }) }, nb)
		-- writefile updates mtime; make sure the stamp differs even on coarse clocks
		vim.uv.fs_utime(nb, os.time() + 5, os.time() + 5)

		assert.is_nil(jupytext._cached_conversion(nb))
	end)

	it("should invalidate when the file is deleted", function()
		jupytext._cache_conversion(nb, "# %%\nold")
		vim.fn.delete(nb)

		assert.is_nil(jupytext._cached_conversion(nb))
	end)
end)

describe("jupytext security", function()
	it("should not contain sh -c wrapping pattern", function()
		local source_path = "lua/pyworks/notebook/jupytext.lua"
		local lines = vim.fn.readfile(source_path)
		local source = table.concat(lines, "\n")
		assert.is_nil(source:match('"sh",%s*"-c"'), "jupytext.lua should not use sh -c wrapping")
	end)
end)
