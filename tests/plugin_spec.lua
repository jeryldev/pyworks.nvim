describe("plugin/pyworks", function()
	local plugin_path = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")

	before_each(function()
		vim.g.loaded_pyworks = nil
		vim.cmd("source " .. vim.fn.fnameescape(plugin_path .. "plugin/pyworks.lua"))
	end)

	describe("FileType autocmd", function()
		it("should set pyworks_filetype_setup_done after first run", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. "/test.py")
			vim.api.nvim_set_current_buf(bufnr)

			vim.bo[bufnr].filetype = "python"
			vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })

			local done = vim.b[bufnr].pyworks_filetype_setup_done
			assert.is_true(done)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should not re-run setup if already done", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. "/test.py")
			vim.api.nvim_set_current_buf(bufnr)

			vim.b[bufnr].pyworks_filetype_setup_done = true

			local ok = pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = bufnr })
			assert.is_true(ok)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)
end)
