-- Handle .ipynb files with jupytext CLI
-- This runs when pyworks.nvim loads as a plugin

-- Our handler for notebooks
vim.api.nvim_create_autocmd("BufReadCmd", {
	pattern = "*.ipynb",
	group = vim.api.nvim_create_augroup("PyworksNotebooks", { clear = true }),
	callback = function(args)
		local filepath = args.file
		local bufnr = args.buf
		
		-- First, try to convert using jupytext CLI directly
		local result = vim.fn.system(string.format("jupytext --to py:percent '%s' --output -", filepath))
		if vim.v.shell_error == 0 and result and result ~= "" then
			-- Successfully converted
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result, "\n"))
			vim.api.nvim_buf_set_option(bufnr, "filetype", "python")
			vim.api.nvim_buf_set_option(bufnr, "modified", false)
			
			-- Set up write command to save back to notebook
			vim.api.nvim_create_autocmd({"BufWriteCmd", "FileWriteCmd"}, {
				buffer = bufnr,
				callback = function()
					-- Get current buffer content
					local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
					local temp_file = vim.fn.tempname() .. ".py"
					
					-- Write to temp file
					local f = io.open(temp_file, "w")
					if f then
						f:write(table.concat(lines, "\n"))
						f:close()
						
						-- Convert back to notebook
						vim.fn.system(string.format("jupytext --to notebook '%s' --output '%s'", temp_file, filepath))
						if vim.v.shell_error == 0 then
							vim.api.nvim_buf_set_option(bufnr, "modified", false)
							vim.notify("Saved notebook: " .. vim.fn.fnamemodify(filepath, ":t"), vim.log.levels.INFO)
						else
							vim.notify("Failed to save notebook", vim.log.levels.ERROR)
						end
						
						-- Clean up temp file
						vim.fn.delete(temp_file)
					end
				end,
			})
			return
		end
		
		-- If jupytext CLI failed, try to fix metadata and retry
		local file = io.open(filepath, "r")
		if file then
			local content = file:read("*all")
			file:close()
			
			local ok, notebook = pcall(vim.json.decode, content)
			if ok and notebook then
				local needs_update = false
				
				-- Ensure metadata exists
				if not notebook.metadata then
					notebook.metadata = {}
					needs_update = true
				end
				
				-- Only add Python metadata if no language is specified at all
				if not notebook.metadata.language_info or not notebook.metadata.language_info.name then
					-- Check if kernelspec exists and has a language
					local language = nil
					if notebook.metadata.kernelspec and notebook.metadata.kernelspec.language then
						language = notebook.metadata.kernelspec.language
					end
					
					-- Default to Python only if no language detected
					if not language then
						notebook.metadata.language_info = {
							codemirror_mode = { name = "ipython", version = 3 },
							file_extension = ".py",
							mimetype = "text/x-python",
							name = "python",
							nbconvert_exporter = "python",
							pygments_lexer = "ipython3",
							version = "3.11.0",
						}
						needs_update = true
					end
				end
				
				-- Only add Python kernelspec if no kernelspec exists at all
				if not notebook.metadata.kernelspec then
					-- Only default to Python if no other language info exists
					if not notebook.metadata.language_info or notebook.metadata.language_info.name == "python" then
						notebook.metadata.kernelspec = {
							display_name = "Python 3",
							language = "python",
							name = "python3",
						}
						needs_update = true
					end
				end
				
				-- Write back if updated and retry
				if needs_update then
					local fixed_json = vim.json.encode(notebook)
					local write_file = io.open(filepath, "w")
					if write_file then
						write_file:write(fixed_json)
						write_file:close()
						
						-- Retry conversion
						result = vim.fn.system(string.format("jupytext --to py:percent '%s' --output -", filepath))
						if vim.v.shell_error == 0 and result and result ~= "" then
							vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result, "\n"))
							vim.api.nvim_buf_set_option(bufnr, "filetype", "python")
							vim.api.nvim_buf_set_option(bufnr, "modified", false)
							return
						end
					end
				end
				
				-- Last resort: show JSON
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
				vim.api.nvim_buf_set_option(bufnr, "filetype", "json")
				vim.api.nvim_buf_set_option(bufnr, "modified", false)
				vim.notify("Showing raw notebook (install jupytext: pip install jupytext)", vim.log.levels.WARN)
			end
		end
	end,
})

-- Remove any conflicting jupytext.nvim autocmds
vim.defer_fn(function()
	local autocmds = vim.api.nvim_get_autocmds({
		event = "BufReadCmd",
		pattern = "*.ipynb",
	})
	for _, autocmd in ipairs(autocmds) do
		if autocmd.group_name == "jupytext" then
			pcall(vim.api.nvim_del_autocmd, autocmd.id)
		end
	end
end, 100)