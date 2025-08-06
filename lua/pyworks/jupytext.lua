-- Jupytext initialization and notebook metadata fixing
local M = {}

-- Setup jupytext configuration and metadata fixing
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
	end
	
	-- Fix notebooks on BufReadPre to ensure metadata exists
	vim.api.nvim_create_autocmd("BufReadPre", {
		pattern = "*.ipynb",
		group = vim.api.nvim_create_augroup("PyworksJupytext", { clear = true }),
		callback = function()
			local filepath = vim.fn.expand("<afile>:p")
			M.fix_notebook_metadata(filepath)
		end,
		desc = "Fix notebook metadata before jupytext reads it",
	})
end

-- Fix notebook metadata for a specific file
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
			return true
		end
	end
	
	return false
end

-- Fix current buffer if it's a notebook
function M.fix_current_notebook()
	local filepath = vim.fn.expand("%:p")
	if not filepath:match("%.ipynb$") then
		vim.notify("Not a notebook file", vim.log.levels.WARN)
		return
	end

	if M.fix_notebook_metadata(filepath) then
		vim.notify("Fixed notebook metadata", vim.log.levels.INFO)
		vim.cmd("edit!") -- Reload the file
	else
		vim.notify("Notebook metadata already correct or could not be fixed", vim.log.levels.INFO)
	end
end

return M