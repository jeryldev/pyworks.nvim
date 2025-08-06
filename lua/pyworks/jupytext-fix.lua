-- Fix for jupytext handling notebooks without language metadata
local M = {}

function M.fix_notebook_metadata(filepath)
	-- Read the file
	local file = io.open(filepath, "r")
	if not file then
		return false
	end
	local content = file:read("*all")
	file:close()

	-- Try to parse as JSON
	local ok, notebook = pcall(vim.json.decode, content)
	if not ok or not notebook then
		return false
	end

	local needs_update = false

	-- Ensure metadata exists
	if not notebook.metadata then
		notebook.metadata = {}
		needs_update = true
	end

	-- Add Python language_info if missing
	if not notebook.metadata.language_info or not notebook.metadata.language_info.name then
		notebook.metadata.language_info = {
			codemirror_mode = {
				name = "ipython",
				version = 3,
			},
			file_extension = ".py",
			mimetype = "text/x-python",
			name = "python",
			nbconvert_exporter = "python",
			pygments_lexer = "ipython3",
			version = "3.11.0",
		}
		needs_update = true
	end

	-- Add Python kernelspec if missing
	if not notebook.metadata.kernelspec then
		notebook.metadata.kernelspec = {
			display_name = "Python 3",
			language = "python",
			name = "python3",
		}
		needs_update = true
	end

	-- Write back to file if updated
	if needs_update then
		local fixed_json = vim.json.encode(notebook)
		local write_file = io.open(filepath, "w")
		if write_file then
			write_file:write(fixed_json)
			write_file:close()
			return true
		end
	end

	return false
end

-- Override jupytext's read function to fix notebooks first
function M.patch_jupytext_read()
	-- Schedule this to run after jupytext loads
	vim.defer_fn(function()
		local ok, jupytext = pcall(require, "jupytext")
		if not ok then
			return
		end

		-- Try to get autocmds without specifying group first
		local autocmds = vim.api.nvim_get_autocmds({
			event = "BufReadCmd",
			pattern = "*.ipynb",
		})

		-- Find and replace jupytext's autocmd
		for _, autocmd in ipairs(autocmds or {}) do
			-- Check if this is likely jupytext's autocmd
			if autocmd.callback and string.match(vim.inspect(autocmd.callback), "jupytext") then
				-- Delete the original
				vim.api.nvim_del_autocmd(autocmd.id)

				-- Create our replacement
				vim.api.nvim_create_autocmd("BufReadCmd", {
					pattern = "*.ipynb",
					callback = function(opts)
						local filepath = vim.fn.expand("<afile>:p")
						-- Fix the notebook first
						local fixed = M.fix_notebook_metadata(filepath)
						if fixed then
							vim.notify("Fixed notebook metadata for: " .. vim.fn.fnamemodify(filepath, ":t"), vim.log.levels.INFO)
						end
						-- Then call jupytext's read function
						jupytext.read_from_ipynb(opts.buf, filepath)
					end,
				})
				break
			end
		end
	end, 100) -- Small delay to ensure jupytext is loaded
end

return M