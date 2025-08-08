-- Keymaps for pyworks.nvim
-- Cell execution with Molten integration for ALL 6 scenarios:
-- 1. Python files (.py) with python3 kernel
-- 2. Julia files (.jl) with julia kernel
-- 3. R files (.R) with ir kernel
-- 4. Python notebooks (.ipynb) with python3 kernel
-- 5. Julia notebooks (.ipynb) with julia kernel
-- 6. R notebooks (.ipynb) with ir kernel
-- ALL use Molten + image.nvim for execution and display

local M = {}

-- Set up keymaps for a buffer
function M.setup_buffer_keymaps()
	local opts = { buffer = true, silent = true }

	-- Check if Molten is available (it's a remote plugin, not a Lua module)
	local has_molten = vim.fn.exists(":MoltenInit") == 2

	if has_molten then
		-- Molten-specific keymaps

		-- Run current line
		vim.keymap.set("n", "<leader>jl", function()
			-- Check if kernel is initialized for this buffer
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.b[bufnr].molten_initialized then
				-- Auto-initialize based on file type
				local ft = vim.bo.filetype
				local detector = require("pyworks.core.detector")
				local kernel = detector.get_kernel_for_language(ft)

				if kernel then
					vim.notify("Initializing " .. kernel .. " kernel...", vim.log.levels.INFO)
					vim.cmd("MoltenInit " .. kernel)
					vim.b[bufnr].molten_initialized = true

					-- Wait a moment then run the line
					vim.defer_fn(function()
						vim.cmd("MoltenEvaluateLine")
						-- Move to next line
						local cursor = vim.api.nvim_win_get_cursor(0)
						local next_line = cursor[1] + 1
						local last_line = vim.api.nvim_buf_line_count(0)
						if next_line <= last_line then
							vim.api.nvim_win_set_cursor(0, { next_line, cursor[2] })
						end
					end, 100)
					return
				end
			end

			-- Kernel should be initialized, run the line
			vim.cmd("MoltenEvaluateLine")

			-- Move to next line for convenience
			local cursor = vim.api.nvim_win_get_cursor(0)
			local next_line = cursor[1] + 1
			local last_line = vim.api.nvim_buf_line_count(0)
			if next_line <= last_line then
				vim.api.nvim_win_set_cursor(0, { next_line, cursor[2] })
			end
		end, vim.tbl_extend("force", opts, { desc = "Molten: Run current line" }))

		-- Run visual selection
		vim.keymap.set(
			"v",
			"<leader>jv",
			":<C-u>MoltenEvaluateVisual<CR>",
			vim.tbl_extend("force", opts, { desc = "Molten: Run selected lines" })
		)

		-- Also support visual block mode
		vim.keymap.set(
			"x",
			"<leader>jv",
			":<C-u>MoltenEvaluateVisual<CR>",
			vim.tbl_extend("force", opts, { desc = "Molten: Run selected block" })
		)

		-- Also allow running in normal mode if there's a visual selection
		vim.keymap.set("n", "<leader>jv", function()
			-- Check if kernel is initialized
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.b[bufnr].molten_initialized then
				-- Auto-initialize based on file type
				local ft = vim.bo.filetype
				local detector = require("pyworks.core.detector")
				local kernel = detector.get_kernel_for_language(ft)

				if kernel then
					vim.notify("Initializing " .. kernel .. " kernel...", vim.log.levels.INFO)
					vim.cmd("MoltenInit " .. kernel)
					vim.b[bufnr].molten_initialized = true

					-- Wait a moment then run the last selection
					vim.defer_fn(function()
						vim.cmd("normal! gv") -- Reselect
						vim.defer_fn(function()
							vim.cmd("MoltenEvaluateVisual")
						end, 50)
					end, 100)
					return
				end
			end

			-- Reselect and run
			vim.cmd("normal! gv") -- Reselect last visual selection
			vim.defer_fn(function()
				vim.cmd("MoltenEvaluateVisual")
			end, 50)
		end, vim.tbl_extend("force", opts, { desc = "Molten: Run visual selection" }))

		-- Select/highlight current cell (between cell markers) or entire file
		vim.keymap.set("n", "<leader>jr", function()
			-- Save current position
			local save_cursor = vim.api.nvim_win_get_cursor(0)

			-- Check if there are any cell markers in the file
			local has_cells = vim.fn.search("^# %%", "nw") > 0

			if has_cells then
				-- Find and select the current cell
				local cell_start = vim.fn.search("^# %%", "bnW") -- Search backwards
				if cell_start == 0 then
					-- We're before the first cell, select from beginning
					vim.cmd("normal! gg")
				else
					vim.cmd("normal! " .. cell_start .. "G")
					vim.cmd("normal! j") -- Move past the cell marker
				end

				vim.cmd("normal! V") -- Start visual line mode

				local cell_end = vim.fn.search("^# %%", "nW") -- Search forwards
				if cell_end == 0 then
					-- We're in the last cell, select to end
					vim.cmd("normal! G")
				else
					vim.cmd("normal! " .. cell_end .. "G")
					vim.cmd("normal! k") -- Don't include the next cell marker
				end
			else
				-- No cell markers, select the entire file
				vim.cmd("normal! ggVG")
				vim.notify("No cell markers found, selected entire file", vim.log.levels.INFO)
			end
		end, vim.tbl_extend("force", opts, { desc = "Select current cell or entire file" }))

		-- Re-evaluate current cell (or use operator to run cell)
		vim.keymap.set("n", "<leader>jc", function()
			-- Check if we have cell markers
			local has_cells = vim.fn.search("^# %%", "nw") > 0
			if has_cells then
				-- Use MoltenEvaluateOperator with text object for cell
				vim.cmd("MoltenEvaluateOperator")
				-- Send 'ic' (inside cell) text object
				vim.api.nvim_feedkeys("ic", "n", false)
			else
				-- No cells, try to re-evaluate or run whole file
				local ok = pcall(vim.cmd, "MoltenReevaluateCell")
				if not ok then
					-- Fall back to running entire file
					vim.cmd("normal! ggVG")
					vim.cmd(":<C-u>MoltenEvaluateVisual<CR>")
				end
			end
		end, vim.tbl_extend("force", opts, { desc = "Molten: Re-evaluate current cell" }))

		-- Delete cell output
		vim.keymap.set("n", "<leader>jd", function()
			vim.cmd("MoltenDelete")
		end, vim.tbl_extend("force", opts, { desc = "Molten: Delete cell output" }))

		-- Show output (useful since auto_open is disabled)
		vim.keymap.set("n", "<leader>jo", function()
			vim.cmd("MoltenShowOutput")
		end, vim.tbl_extend("force", opts, { desc = "Molten: Show output window" }))

		-- Hide output window
		vim.keymap.set("n", "<leader>jh", function()
			vim.cmd("MoltenHideOutput")
		end, vim.tbl_extend("force", opts, { desc = "Molten: Hide output window" }))

		-- Enter output window (to interact with it)
		vim.keymap.set("n", "<leader>je", function()
			vim.cmd("MoltenEnterOutput")
		end, vim.tbl_extend("force", opts, { desc = "Molten: Enter output window" }))

		-- Hover to show output (using K or gh)
		vim.keymap.set("n", "K", function()
			-- Check if we're on a cell that has output
			local ok, _ = pcall(vim.cmd, "MoltenShowOutput")
			if not ok then
				-- Fall back to default K behavior (show hover docs)
				vim.lsp.buf.hover()
			end
		end, vim.tbl_extend("force", opts, { desc = "Show Molten output or LSP hover" }))
	else
		-- Fallback keymaps when Molten is not available
		-- These just select text for manual copying

		vim.keymap.set("n", "<leader>jr", function()
			-- Highlight/select current cell
			vim.cmd("normal! ?^# %%\\|^```\\|^```{<CR>") -- Go to cell start
			vim.cmd("normal! V") -- Start visual line mode
			vim.cmd("normal! /^# %%\\|^```\\|^```{<CR>") -- Go to next cell start
			vim.cmd("normal! k") -- Go up one line to exclude next cell marker
			vim.notify("Molten not available. Cell selected for manual copy.", vim.log.levels.WARN)
		end, vim.tbl_extend("force", opts, { desc = "Select current cell (Molten not available)" }))

		vim.keymap.set("v", "<leader>jv", function()
			vim.notify("Molten not available. Copy selection to run elsewhere.", vim.log.levels.WARN)
		end, vim.tbl_extend("force", opts, { desc = "Run selected lines (Molten not available)" }))

		vim.keymap.set("n", "<leader>jl", function()
			vim.notify("Molten not available. Use :MoltenInit to initialize.", vim.log.levels.WARN)
		end, vim.tbl_extend("force", opts, { desc = "Run current line (Molten not available)" }))
	end

	-- Cell navigation (works with or without Molten)
	-- Using ]j and [j for cell navigation (avoiding ]c/[c which LazyVim uses)
	vim.keymap.set("n", "]j", function()
		-- Search for next cell marker (# %% for Python/Julia/R notebooks)
		local found = vim.fn.search("^# %%", "W")
		if found == 0 then
			vim.notify("No more cells", vim.log.levels.INFO)
		end
	end, vim.tbl_extend("force", opts, { desc = "Jump to next cell" }))

	vim.keymap.set("n", "[j", function()
		-- Search for previous cell marker
		local found = vim.fn.search("^# %%", "bW")
		if found == 0 then
			vim.notify("No previous cells", vim.log.levels.INFO)
		end
	end, vim.tbl_extend("force", opts, { desc = "Jump to previous cell" }))
end

-- Set up Molten kernel management keymaps
function M.setup_molten_keymaps()
	local opts = { buffer = true, silent = true }

	-- Check if Molten is available (it's a remote plugin, not a Lua module)
	local has_molten = vim.fn.exists(":MoltenInit") == 2

	if has_molten then
		-- Initialize Molten kernel for current file type
		vim.keymap.set("n", "<leader>mi", function()
			local ft = vim.bo.filetype
			local ext = vim.fn.expand("%:e")

			-- Determine kernel based on file type or extension
			local kernel = nil
			if ft == "python" or (ext == "ipynb" and ft == "") then
				kernel = "python3"
			elseif ft == "julia" then
				kernel = "julia"
			elseif ft == "r" then
				kernel = "ir" -- IRkernel for R
			end

			if kernel then
				vim.cmd("MoltenInit " .. kernel)
				vim.notify("Initialized Molten with " .. kernel .. " kernel", vim.log.levels.INFO)
			else
				-- Let user choose
				vim.cmd("MoltenInit")
			end
		end, vim.tbl_extend("force", opts, { desc = "Molten: Initialize kernel" }))

		-- Restart kernel
		vim.keymap.set("n", "<leader>mr", function()
			vim.cmd("MoltenRestart")
		end, vim.tbl_extend("force", opts, { desc = "Molten: Restart kernel" }))

		-- Interrupt execution
		vim.keymap.set("n", "<leader>mx", function()
			vim.cmd("MoltenInterrupt")
		end, vim.tbl_extend("force", opts, { desc = "Molten: Interrupt execution" }))

		-- Import notebook (for .ipynb files)
		vim.keymap.set("n", "<leader>mn", function()
			local ext = vim.fn.expand("%:e")
			if ext == "ipynb" then
				vim.cmd("MoltenImportOutput")
				vim.notify("Imported notebook outputs", vim.log.levels.INFO)
			else
				vim.notify("Not a notebook file", vim.log.levels.WARN)
			end
		end, vim.tbl_extend("force", opts, { desc = "Molten: Import notebook outputs" }))

		-- Save outputs
		vim.keymap.set("n", "<leader>ms", function()
			vim.cmd("MoltenSave")
		end, vim.tbl_extend("force", opts, { desc = "Molten: Save outputs" }))
	end
end

return M
