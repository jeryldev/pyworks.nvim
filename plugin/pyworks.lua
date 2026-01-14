-- pyworks.nvim - Plugin loader
-- This file is automatically loaded by Neovim

if vim.g.loaded_pyworks then
	return
end
vim.g.loaded_pyworks = 1

-- Emergency Molten disable via environment variable
if vim.env.PYWORKS_NO_MOLTEN then
	vim.g.molten_error_detected = true
	vim.notify("Molten disabled via PYWORKS_NO_MOLTEN environment variable", vim.log.levels.WARN)
end

-- Create autocmd group for pyworks
local augroup = vim.api.nvim_create_augroup("Pyworks", { clear = true })

-- Check if a file is in a pyworks-managed directory using utils.find_project_root
local function is_pyworks_project(filepath)
	local dir = filepath and vim.fn.fnamemodify(filepath, ":h") or vim.fn.getcwd()
	local utils = require("pyworks.utils")
	local project_root = utils.find_project_root(dir)
	return project_root ~= nil
end

-- Set up autocmds for file detection
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
	group = augroup,
	pattern = { "*.py" }, -- Removed *.ipynb to let jupytext handle it first
	callback = function(ev)
		-- Get the actual buffer number and its full path
		local bufnr = ev.buf
		local full_path = vim.api.nvim_buf_get_name(bufnr)

		-- Use the full path for project detection
		local check_path = full_path ~= "" and full_path or ev.file

		-- For Python files, ALWAYS run pyworks (it will create venv if needed)
		-- For other languages, check for project markers
		local ext = vim.fn.fnamemodify(check_path, ":e")
		local ft = vim.bo[bufnr].filetype

		-- Always process Python files and notebooks
		if ext ~= "py" and ext ~= "ipynb" and ft ~= "python" then
			-- For non-Python files, check for project markers
			if not is_pyworks_project(check_path) then
				return
			end
		end

		-- Debug: Show that autocmd fired
		if vim.g.pyworks_debug then
			vim.notify("[Pyworks] File opened: " .. check_path, vim.log.levels.DEBUG)
		end

		-- Use defer_fn for non-blocking operation
		vim.defer_fn(function()
			local detector = require("pyworks.core.detector")
			-- Use the full path directly
			detector.on_file_open(full_path)
		end, 100) -- Small delay to let buffer settle
	end,
	desc = "Pyworks: Detect and handle file type",
})

-- Re-scan on save for new imports
vim.api.nvim_create_autocmd("BufWritePost", {
	group = augroup,
	pattern = { "*.py", "*.ipynb" },
	callback = function(ev)
		-- Only run in project directories (check the file's location)
		if not is_pyworks_project(ev.file) then
			return
		end

		vim.defer_fn(function()
			local detector = require("pyworks.core.detector")
			detector.rescan_imports(ev.file)
		end, 100)
	end,
	desc = "Pyworks: Re-scan imports after save",
})

-- Set up keymaps for package installation and cell execution
vim.api.nvim_create_autocmd("FileType", {
	group = augroup,
	pattern = { "python" },
	callback = function(ev)
		-- Only set up keymaps in project directories (check the file's location)
		local filepath = vim.api.nvim_buf_get_name(ev.buf)
		if not is_pyworks_project(filepath) then
			-- Still set up Molten keymaps even outside projects
			local keymaps = require("pyworks.keymaps")
			keymaps.setup_buffer_keymaps()
			keymaps.setup_molten_keymaps()
			return
		end

		-- Package installation keymap
		vim.keymap.set("n", "<leader>pi", function()
			local python = require("pyworks.languages.python")
			python.install_missing_packages()
		end, { buffer = true, desc = "Pyworks: Install missing packages" })

		-- Set up cell execution keymaps for Molten
		local keymaps = require("pyworks.keymaps")
		keymaps.setup_buffer_keymaps()
		keymaps.setup_molten_keymaps()

		-- Set up UI enhancements (cell numbering and highlighting)
		local ui = require("pyworks.ui")
		ui.setup_buffer({ show_cell_numbers = true, enable_cell_folding = false })

		-- For notebooks (.ipynb files converted by jupytext), trigger auto-initialization
		-- This is needed because jupytext changes the filetype after conversion
		if filepath:match("%.ipynb$") then
			-- Check if jupytext successfully converted the file
			local first_line = vim.api.nvim_buf_get_lines(ev.buf, 0, 1, false)[1] or ""
			if first_line:match("^{") then
				-- It's still JSON, jupytext didn't work
				local utils = require("pyworks.utils")
				local project_dir, venv_path = utils.get_project_paths(filepath)
				local project_type = utils.detect_project_type(project_dir)
				local project_rel = vim.fn.fnamemodify(project_dir, ":~:.")

				vim.notify(
					string.format("[Error] %s notebook not converted: jupytext missing", project_type),
					vim.log.levels.ERROR
				)
				vim.notify(
					string.format("[Hint] Run :PyworksSetup to create venv at: %s/.venv", project_rel),
					vim.log.levels.INFO
				)
				return
			end

			-- Jupytext worked, handle the notebook
			vim.defer_fn(function()
				local detector = require("pyworks.core.detector")
				detector.handle_python_notebook(filepath)
			end, 200) -- Delay to ensure everything is ready
		end
	end,
	desc = "Pyworks: Set up language-specific keymaps and auto-init for notebooks",
})

-- Helper function to reload a notebook buffer properly
-- Follows the same pattern as open_and_verify_notebook in commands/create.lua
--
-- IMPORTANT: This function can trigger cascading autocmds (BufReadCmd, BufEnter, etc.)
-- which could cause infinite recursion with MoltenTick. The recursion_guard module
-- prevents this by:
--   1. Checking if a reload is already in progress (global and per-buffer locks)
--   2. Debouncing rapid successive reload attempts
--   3. Temporarily slowing Molten's tick rate during reload
--   4. Limiting maximum recursion depth
local function reload_notebook_buffer(filepath, opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

	-- Use recursion guard to prevent infinite loops
	local guard = require("pyworks.core.recursion_guard")

	-- Check if reload is safe (not already in progress, not debounced)
	if not guard.can_reload(bufnr) then
		if vim.g.pyworks_debug then
			vim.notify("[pyworks] Reload blocked by recursion guard: " .. filepath, vim.log.levels.DEBUG)
		end
		return false
	end

	-- Begin protected reload operation
	local release = guard.begin_reload(bufnr)

	-- Wrap in pcall to ensure we always release the guard
	local success, result = pcall(function()
		-- Deinitialize Molten first to clean up stale extmarks
		-- This prevents IndexError when Molten tries to access invalid extmark positions
		if vim.fn.exists(":MoltenDeinit") == 2 then
			pcall(vim.cmd, "MoltenDeinit")
		end

		-- Ensure notebook handler is configured before reloading
		local jupytext = require("pyworks.notebook.jupytext")
		jupytext.configure_notebook_handler()

		-- Use :edit to open fresh from disk - this triggers BufReadCmd
		local ok = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(filepath))

		if ok then
			-- Verify conversion worked (buffer should NOT start with '{')
			local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
			if first_line:match("^%s*{") then
				-- Still JSON, try configuring and reloading once more
				jupytext.configure_notebook_handler()
				pcall(vim.cmd, "edit!")
			end
		end

		return ok
	end)

	-- Always release the guard, even if reload failed
	release()

	if not success then
		vim.notify("[pyworks] Reload error: " .. tostring(result), vim.log.levels.ERROR)
		return false
	end

	return result
end

-- Manual command to reload current notebook (useful after session restore)
vim.api.nvim_create_user_command("PyworksReloadNotebook", function()
	local filepath = vim.api.nvim_buf_get_name(0)
	if not filepath:match("%.ipynb$") then
		vim.notify("Not a notebook file", vim.log.levels.WARN)
		return
	end
	-- Expand path to handle ~ and resolve symlinks
	filepath = vim.fn.expand(filepath)
	filepath = vim.fn.resolve(filepath)

	if vim.fn.filereadable(filepath) ~= 1 then
		vim.notify("File not found: " .. filepath, vim.log.levels.ERROR)
		vim.notify("Buffer name: " .. vim.api.nvim_buf_get_name(0), vim.log.levels.INFO)
		return
	end
	reload_notebook_buffer(filepath)
end, { desc = "Reload current notebook with jupytext conversion" })

-- Handle session restore: re-trigger notebook conversion for .ipynb files
-- Session restore bypasses BufReadCmd, leaving notebooks blank or as raw JSON
--
-- IMPORTANT: Session restore can trigger multiple buffer loads simultaneously.
-- We collect all notebooks that need reloading and process them sequentially
-- to avoid overwhelming Molten and causing recursion issues.
vim.api.nvim_create_autocmd("SessionLoadPost", {
	group = augroup,
	callback = function()
		local guard = require("pyworks.core.recursion_guard")

		-- IMMEDIATELY deinit Molten for all .ipynb buffers to clean up stale extmarks
		-- This prevents IndexError when Molten tries to access invalid extmark positions
		-- Must run synchronously before any Molten operations
		if vim.fn.exists(":MoltenDeinit") == 2 then
			for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(bufnr) then
					local filepath = vim.api.nvim_buf_get_name(bufnr)
					if filepath:match("%.ipynb$") then
						vim.api.nvim_buf_call(bufnr, function()
							pcall(vim.cmd, "MoltenDeinit")
						end)
					end
				end
			end
		end

		-- Then defer the buffer reloading
		vim.defer_fn(function()
			-- Check if a reload is already in progress (from another source)
			if guard.is_reloading() then
				if vim.g.pyworks_debug then
					vim.notify("[pyworks] SessionLoadPost skipped: reload in progress", vim.log.levels.DEBUG)
				end
				return
			end

			-- Collect all notebooks that need reloading
			local notebooks_to_reload = {}
			for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(bufnr) then
					local filepath = vim.api.nvim_buf_get_name(bufnr)
					if filepath:match("%.ipynb$") and filepath ~= "" and vim.fn.filereadable(filepath) == 1 then
						-- Check if buffer is empty or still raw JSON (not converted)
						local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
						local first_line = lines[1] or ""
						local is_empty = #lines == 0 or (first_line == "" and #lines == 1)
						local is_json = first_line:match("^%s*{")

						if is_empty or is_json then
							table.insert(notebooks_to_reload, { bufnr = bufnr, filepath = filepath })
						end
					end
				end
			end

			-- Process notebooks sequentially to avoid overwhelming Molten
			-- Each reload waits for the previous one to complete via debounce
			local function reload_next(index)
				if index > #notebooks_to_reload then
					return
				end

				local notebook = notebooks_to_reload[index]
				if vim.api.nvim_buf_is_valid(notebook.bufnr) then
					vim.api.nvim_set_current_buf(notebook.bufnr)
					reload_notebook_buffer(notebook.filepath, { bufnr = notebook.bufnr })
				end

				-- Schedule next reload after debounce period
				vim.defer_fn(function()
					reload_next(index + 1)
				end, 600) -- Slightly longer than debounce to ensure sequential processing
			end

			if #notebooks_to_reload > 0 then
				reload_next(1)
			end
		end, 500) -- Longer delay to ensure session is fully loaded
	end,
	desc = "Pyworks: Re-process notebooks after session restore",
})

-- Fallback: Handle BufWinEnter for notebooks that might have been missed
-- BufWinEnter fires when buffer is displayed in a window
--
-- IMPORTANT: This autocmd can cause infinite recursion if not properly guarded:
--   BufWinEnter -> reload_notebook_buffer -> :edit -> BufReadCmd -> BufEnter -> ...
-- The recursion_guard module prevents this, but we also check early here to avoid
-- unnecessary work when a reload is already in progress.
vim.api.nvim_create_autocmd("BufWinEnter", {
	group = augroup,
	pattern = "*.ipynb",
	callback = function(ev)
		-- CRITICAL: Check recursion guard FIRST before any other processing
		-- This prevents cascading reloads that cause E132 maxfuncdepth errors
		local guard = require("pyworks.core.recursion_guard")
		if guard.is_reloading() then
			if vim.g.pyworks_debug then
				vim.notify("[pyworks] BufWinEnter skipped: reload in progress", vim.log.levels.DEBUG)
			end
			return
		end

		local filepath = vim.api.nvim_buf_get_name(ev.buf)

		-- Skip if no filepath or file doesn't exist
		if filepath == "" or vim.fn.filereadable(filepath) ~= 1 then
			return
		end

		-- Check if buffer needs conversion (empty or raw JSON)
		local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, 1, false)
		local first_line = lines[1] or ""
		local is_empty = #lines == 0 or (first_line == "" and #lines == 1)
		local is_json = first_line:match("^%s*{")

		if is_empty or is_json then
			-- Skip if already being processed (buffer-local flag)
			local ok, processing = pcall(vim.api.nvim_buf_get_var, ev.buf, "pyworks_notebook_processing")
			if ok and processing then
				return
			end
			pcall(vim.api.nvim_buf_set_var, ev.buf, "pyworks_notebook_processing", true)

			-- Defer to let other handlers complete first
			vim.defer_fn(function()
				-- Re-check recursion guard in deferred callback
				if guard.is_reloading() then
					pcall(vim.api.nvim_buf_del_var, ev.buf, "pyworks_notebook_processing")
					return
				end

				-- Double-check the buffer still exists and needs processing
				if not vim.api.nvim_buf_is_valid(ev.buf) then
					return
				end

				local check_lines = vim.api.nvim_buf_get_lines(ev.buf, 0, 1, false)
				local check_first = check_lines[1] or ""
				local still_empty = #check_lines == 0 or (check_first == "" and #check_lines == 1)
				local still_json = check_first:match("^%s*{")

				if still_empty or still_json then
					reload_notebook_buffer(filepath, { bufnr = ev.buf })
				end

				-- Clear processing flag after completion
				pcall(vim.api.nvim_buf_del_var, ev.buf, "pyworks_notebook_processing")
			end, 500) -- Longer delay
		end
	end,
	desc = "Pyworks: Handle notebooks that bypass normal loading",
})
