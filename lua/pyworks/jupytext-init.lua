-- Jupytext initialization and notebook metadata fixing
local M = {}

-- Ensure notebooks have proper metadata before jupytext reads them
function M.setup()
	-- Patch jupytext config as soon as it's available
	local ok, jupytext = pcall(require, "jupytext")
	if ok then
		-- Ensure config has defaults
		jupytext.config = vim.tbl_deep_extend("force", {
			style = "percent",
			output_extension = "py",
			force_ft = "python",
			custom_language_formatting = {},
		}, jupytext.config or {})
		-- Silently patched jupytext config
	end
	
	-- Fix notebooks on BufReadPre to ensure metadata exists
	vim.api.nvim_create_autocmd("BufReadPre", {
		pattern = "*.ipynb",
		group = vim.api.nvim_create_augroup("PyworksJupytext", { clear = true }),
		callback = function()
			local filepath = vim.fn.expand("<afile>:p")
			
			-- Read the notebook file
			local file = io.open(filepath, "r")
			if not file then
				return
			end
			
			local content = file:read("*all")
			file:close()
			
			-- Parse JSON
			local ok, notebook = pcall(vim.json.decode, content)
			if not ok or not notebook then
				return
			end
			
			local needs_update = false
			
			-- Ensure metadata exists
			if not notebook.metadata then
				notebook.metadata = {}
				needs_update = true
			end
			
			-- Only add Python metadata if no language is specified
			if not notebook.metadata.language_info or not notebook.metadata.language_info.name then
				-- Check if kernelspec has a language hint
				local language = nil
				if notebook.metadata.kernelspec and notebook.metadata.kernelspec.language then
					language = notebook.metadata.kernelspec.language
				end
				
				-- Only default to Python if no language detected
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
			
			-- Only add Python kernelspec if missing and appropriate
			if not notebook.metadata.kernelspec then
				if not notebook.metadata.language_info or notebook.metadata.language_info.name == "python" then
					notebook.metadata.kernelspec = {
						display_name = "Python 3",
						language = "python",
						name = "python3",
					}
					needs_update = true
				end
			end
			
			-- Write back if updated
			if needs_update then
				local fixed_json = vim.json.encode(notebook)
				local write_file = io.open(filepath, "w")
				if write_file then
					write_file:write(fixed_json)
					write_file:close()
					-- Silently fixed notebook metadata
				end
			end
		end,
		desc = "Fix notebook metadata before jupytext reads it",
	})
end

return M