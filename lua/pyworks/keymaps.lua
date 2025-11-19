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

local error_handler = require("pyworks.core.error_handler")

-- Set up keymaps for a buffer
function M.setup_buffer_keymaps()
	local opts = { buffer = true, silent = true }

	-- Check if Molten is available (it's a remote plugin, not a Lua module)
	local has_molten = vim.fn.exists(":MoltenInit") == 2

	if has_molten then
		-- Molten-specific keymaps

		-- ============================================================================
		-- CELL EXECUTION
		-- ============================================================================

		-- Run current line
		vim.keymap.set("n", "<leader>jl", function()
			-- Check if kernel is initialized for this buffer
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.b[bufnr].molten_initialized then
				-- Auto-initialize based on file type
				local ft = vim.bo.filetype
				local filepath = vim.api.nvim_buf_get_name(bufnr)
				local detector = require("pyworks.core.detector")
				-- Pass filepath for project-aware kernel selection
				local kernel = detector.get_kernel_for_language(ft, filepath)

				if kernel then
					vim.notify("Initializing " .. kernel .. " kernel...", vim.log.levels.INFO)
					local ok =
						error_handler.protected_call(vim.cmd, "Failed to initialize kernel", "MoltenInit " .. kernel)
					if ok then
						vim.b[bufnr].molten_initialized = true
					end

					-- Wait a moment then run the line
					vim.defer_fn(function()
						error_handler.protected_call(vim.cmd, "Failed to evaluate line", "MoltenEvaluateLine")
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
			"<leader>jr",
			":<C-u>MoltenEvaluateVisual<CR>",
			vim.tbl_extend("force", opts, { desc = "Run selection" })
		)

		-- Also support visual block mode
		vim.keymap.set(
			"x",
			"<leader>jr",
			":<C-u>MoltenEvaluateVisual<CR>",
			vim.tbl_extend("force", opts, { desc = "Run selection" })
		)

		-- Run current cell and move to next (classic Jupyter Shift+Enter)
		vim.keymap.set("n", "<leader>jc", function()
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.b[bufnr].molten_initialized then
				vim.notify("⚠️  No kernel initialized. Press <leader>jl to auto-initialize.", vim.log.levels.WARN)
				return
			end

			-- Re-evaluate current cell
			error_handler.protected_call(vim.cmd, "Failed to evaluate cell", "MoltenReevaluateCell")

			-- Move to next cell
			local found = vim.fn.search("^# %%", "W")
			if found == 0 then
				vim.notify("Last cell", vim.log.levels.INFO)
			end
		end, vim.tbl_extend("force", opts, { desc = "Run cell and move to next" }))

		-- Re-evaluate current cell (stay in place)
		vim.keymap.set("n", "<leader>je", function()
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.b[bufnr].molten_initialized then
				vim.notify("⚠️  No kernel initialized. Press <leader>jl to auto-initialize.", vim.log.levels.WARN)
				return
			end

			error_handler.protected_call(vim.cmd, "Failed to re-evaluate cell", "MoltenReevaluateCell")
		end, vim.tbl_extend("force", opts, { desc = "Re-evaluate current cell" }))

		-- ============================================================================
		-- CELL SELECTION & NAVIGATION
		-- ============================================================================

		-- Visual select current cell (changed from jc to jv)
		vim.keymap.set("n", "<leader>jv", function()
			-- Check if Python provider is working
			if vim.bo.filetype == "python" and not vim.g.python3_host_prog then
				vim.notify("⚠️  Python host not configured. Run :PyworksSetup first", vim.log.levels.WARN)
				return
			end

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
		end, vim.tbl_extend("force", opts, { desc = "Visual select current cell" }))

		-- Go to cell N
		vim.keymap.set("n", "<leader>jg", function()
			vim.ui.input({ prompt = "Go to cell number: " }, function(input)
				if input and input ~= "" then
					local cell_num = tonumber(input)
					if cell_num then
						error_handler.protected_call(vim.cmd, "Failed to go to cell", "MoltenGoto " .. cell_num)
					else
						vim.notify("Invalid cell number", vim.log.levels.ERROR)
					end
				end
			end)
		end, vim.tbl_extend("force", opts, { desc = "Go to cell N" }))

		-- ============================================================================
		-- OUTPUT MANAGEMENT
		-- ============================================================================

		-- Delete cell output
		vim.keymap.set("n", "<leader>jd", function()
			error_handler.protected_call(vim.cmd, "Failed to delete output", "MoltenDelete")
		end, vim.tbl_extend("force", opts, { desc = "Delete cell output" }))

		-- Hide output window
		vim.keymap.set("n", "<leader>jh", function()
			error_handler.protected_call(vim.cmd, "Failed to hide output", "MoltenHideOutput")
		end, vim.tbl_extend("force", opts, { desc = "Hide output window" }))

		-- Enter/open output window
		vim.keymap.set("n", "<leader>jo", function()
			error_handler.protected_call(vim.cmd, "Failed to enter output", "noautocmd MoltenEnterOutput")
		end, vim.tbl_extend("force", opts, { desc = "Enter output window" }))

		-- Hover to show output (using K)
		vim.keymap.set("n", "K", function()
			-- Check if we're on a cell that has output
			local ok, _ = pcall(vim.cmd, "MoltenShowOutput")
			if not ok then
				-- Fall back to default K behavior (show hover docs)
				vim.lsp.buf.hover()
			end
		end, vim.tbl_extend("force", opts, { desc = "Show Molten output or LSP hover" }))
		-- ============================================================================
		-- CELL CREATION
		-- ============================================================================

		-- Insert code cell above
		vim.keymap.set("n", "<leader>ja", function()
			local cell_start = vim.fn.search("^# %%", "bnW")
			local insert_line = cell_start > 0 and cell_start - 1 or 0

			vim.fn.append(insert_line, { "# %%", "" })
			vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
			vim.cmd("startinsert")
		end, vim.tbl_extend("force", opts, { desc = "Insert code cell above" }))

		-- Insert code cell below
		vim.keymap.set("n", "<leader>jb", function()
			local cell_end = vim.fn.search("^# %%", "nW")
			local insert_line

			if cell_end == 0 then
				-- No next cell, insert at end
				insert_line = vim.fn.line("$")
			else
				-- Insert before next cell
				insert_line = cell_end - 1
			end

			vim.fn.append(insert_line, { "", "# %%", "" })
			vim.api.nvim_win_set_cursor(0, { insert_line + 3, 0 })
			vim.cmd("startinsert")
		end, vim.tbl_extend("force", opts, { desc = "Insert code cell below" }))

		-- Insert markdown cell above
		vim.keymap.set("n", "<leader>jma", function()
			local cell_start = vim.fn.search("^# %%", "bnW")
			local insert_line = cell_start > 0 and cell_start - 1 or 0

			vim.fn.append(insert_line, { "# %% [markdown]", "# " })
			vim.api.nvim_win_set_cursor(0, { insert_line + 2, 2 })
			vim.cmd("startinsert!")
		end, vim.tbl_extend("force", opts, { desc = "Insert markdown cell above" }))

		-- Insert markdown cell below
		vim.keymap.set("n", "<leader>jmb", function()
			local cell_end = vim.fn.search("^# %%", "nW")
			local insert_line

			if cell_end == 0 then
				insert_line = vim.fn.line("$")
			else
				insert_line = cell_end - 1
			end

			vim.fn.append(insert_line, { "", "# %% [markdown]", "# " })
			vim.api.nvim_win_set_cursor(0, { insert_line + 3, 2 })
			vim.cmd("startinsert!")
		end, vim.tbl_extend("force", opts, { desc = "Insert markdown cell below" }))

		-- ============================================================================
		-- CELL OPERATIONS
		-- ============================================================================

		-- Toggle cell type (code ↔ markdown)
		vim.keymap.set("n", "<leader>jt", function()
			local cell_start = vim.fn.search("^# %%", "bnW")
			if cell_start == 0 then
				vim.notify("Not in a cell", vim.log.levels.WARN)
				return
			end

			local line = vim.fn.getline(cell_start)
			local new_line

			if line:match("^# %%%s*%[markdown%]") then
				-- Convert to code cell
				new_line = "# %%"
				vim.notify("Converted to code cell", vim.log.levels.INFO)
			else
				-- Convert to markdown cell
				new_line = "# %% [markdown]"
				vim.notify("Converted to markdown cell", vim.log.levels.INFO)
			end

			vim.fn.setline(cell_start, new_line)
		end, vim.tbl_extend("force", opts, { desc = "Toggle cell type" }))

		-- Merge with cell below
		vim.keymap.set("n", "<leader>jJ", function()
			local next_cell = vim.fn.search("^# %%", "nW")
			if next_cell == 0 then
				vim.notify("No cell below to merge", vim.log.levels.WARN)
				return
			end

			-- Delete the next cell marker line
			vim.fn.deletebufline("%", next_cell)
			vim.notify("Merged with cell below", vim.log.levels.INFO)
		end, vim.tbl_extend("force", opts, { desc = "Merge with cell below" }))

		-- Split cell at cursor
		vim.keymap.set("n", "<leader>js", function()
			local cursor_line = vim.fn.line(".")
			vim.fn.append(cursor_line, { "", "# %%", "" })
			vim.api.nvim_win_set_cursor(0, { cursor_line + 3, 0 })
			vim.notify("Cell split", vim.log.levels.INFO)
		end, vim.tbl_extend("force", opts, { desc = "Split cell at cursor" }))
	else
		-- Fallback keymaps when Molten is not available
		-- These just select text for manual copying

		vim.keymap.set("n", "<leader>jv", function()
			-- Highlight/select current cell
			vim.cmd("normal! ?^# %%\\|^```\\|^```{<CR>") -- Go to cell start
			vim.cmd("normal! V") -- Start visual line mode
			vim.cmd("normal! /^# %%\\|^```\\|^```{<CR>") -- Go to next cell start
			vim.cmd("normal! k") -- Go up one line to exclude next cell marker
			vim.notify("Molten not available. Cell selected for manual copy.", vim.log.levels.WARN)
		end, vim.tbl_extend("force", opts, { desc = "Select current cell (Molten not available)" }))

		vim.keymap.set("v", "<leader>jr", function()
			vim.notify("Molten not available. Copy selection to run elsewhere.", vim.log.levels.WARN)
		end, vim.tbl_extend("force", opts, { desc = "Run selection (Molten not available)" }))

		vim.keymap.set("n", "<leader>jl", function()
			vim.notify("Molten not available. Use :MoltenInit to initialize.", vim.log.levels.WARN)
		end, vim.tbl_extend("force", opts, { desc = "Run current line (Molten not available)" }))
	end

	-- Cell navigation (works with or without Molten)
	vim.keymap.set("n", "<leader>j]", function()
		-- Search for next cell marker (# %% for Python/Julia/R notebooks)
		local found = vim.fn.search("^# %%", "W")
		if found == 0 then
			vim.notify("No more cells", vim.log.levels.INFO)
		end
	end, vim.tbl_extend("force", opts, { desc = "Next cell" }))

	vim.keymap.set("n", "<leader>j[", function()
		-- Search for previous cell marker
		local found = vim.fn.search("^# %%", "bW")
		if found == 0 then
			vim.notify("No previous cells", vim.log.levels.INFO)
		end
	end, vim.tbl_extend("force", opts, { desc = "Previous cell" }))
end

-- Set up Molten kernel management keymaps
function M.setup_molten_keymaps()
	local opts = { buffer = true, silent = true }

	-- Check if Molten is available (it's a remote plugin, not a Lua module)
	local has_molten = vim.fn.exists(":MoltenInit") == 2

	if has_molten then
		-- Initialize kernel manually
		vim.keymap.set("n", "<leader>mi", function()
			vim.ui.input({ prompt = "Kernel name: " }, function(input)
				if input and input ~= "" then
					vim.cmd("MoltenInit " .. input)
				end
			end)
		end, vim.tbl_extend("force", opts, { desc = "Initialize kernel" }))

		-- Restart kernel (when things go wrong)
		vim.keymap.set("n", "<leader>mr", function()
			vim.cmd("MoltenRestart")
		end, vim.tbl_extend("force", opts, { desc = "Restart kernel" }))

		-- Interrupt execution (stop long-running code)
		vim.keymap.set("n", "<leader>mx", function()
			vim.cmd("MoltenInterrupt")
		end, vim.tbl_extend("force", opts, { desc = "Interrupt execution" }))

		-- Show kernel info
		vim.keymap.set("n", "<leader>mI", function()
			vim.cmd("MoltenInfo")
		end, vim.tbl_extend("force", opts, { desc = "Show kernel info" }))
	end
end

return M
