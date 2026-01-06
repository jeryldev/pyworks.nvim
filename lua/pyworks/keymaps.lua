-- Keymaps for pyworks.nvim
-- Cell execution with Molten integration for Python:
-- 1. Python files (.py) with python3 kernel
-- 2. Python notebooks (.ipynb) with python3 kernel
-- Uses Molten + image.nvim for execution and display

local M = {}

local error_handler = require("pyworks.core.error_handler")

-- Helper function to find and execute code between # %% markers
-- This creates a Molten cell if one doesn't exist yet
local function evaluate_percent_cell()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)

	-- Find cell boundaries
	local cell_start = vim.fn.search("^# %%", "bnW") -- Search backwards for cell start
	local cell_end = vim.fn.search("^# %%", "nW") -- Search forwards for next cell start

	local start_line, end_line

	if cell_start == 0 and cell_end == 0 then
		-- No cell markers found, evaluate entire file
		start_line = 1
		end_line = vim.fn.line("$")
	elseif cell_start == 0 then
		-- Before first cell marker, select from start to line before first marker
		start_line = 1
		end_line = cell_end - 1
	elseif cell_end == 0 then
		-- After last cell marker, select from line after marker to end
		start_line = cell_start + 1
		end_line = vim.fn.line("$")
	else
		-- Between markers: from line after first marker to line before next marker
		start_line = cell_start + 1
		end_line = cell_end - 1
	end

	-- Ensure we have valid content to execute (not just empty lines or markers)
	if start_line > end_line then
		vim.notify("Empty cell", vim.log.levels.WARN)
		return
	end

	-- Execute the range by entering visual mode and calling MoltenEvaluateVisual from within it
	-- We use vim.api.nvim_feedkeys to simulate the user's keystrokes
	-- This keeps us in visual mode when MoltenEvaluateVisual is called
	local keys = vim.api.nvim_replace_termcodes(
		string.format("%dGV%dG:<C-u>MoltenEvaluateVisual<CR>", start_line, end_line),
		true,
		false,
		true
	)
	vim.api.nvim_feedkeys(keys, "x", false)
end

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

			-- Mark cell as executed
			local ui = require("pyworks.ui")
			local cell_num = ui.get_current_cell_number()
			ui.mark_cell_executed(cell_num)

			-- Always evaluate the # %% delimited cell
			-- This works whether or not a Molten cell already exists
			evaluate_percent_cell()

			-- Move to next cell marker after a short delay to ensure evaluation starts
			vim.defer_fn(function()
				local found = vim.fn.search("^# %%", "W")
				if found == 0 then
					vim.notify("Last cell", vim.log.levels.INFO)
				else
					-- Move to the line after the cell marker (first line of code)
					vim.cmd("normal! j")
				end
			end, 100)
		end, vim.tbl_extend("force", opts, { desc = "Run cell and move to next" }))

		-- Re-evaluate current cell (stay in place)
		vim.keymap.set("n", "<leader>je", function()
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.b[bufnr].molten_initialized then
				vim.notify("⚠️  No kernel initialized. Press <leader>jl to auto-initialize.", vim.log.levels.WARN)
				return
			end

			-- Mark cell as executed
			local ui = require("pyworks.ui")
			local cell_num = ui.get_current_cell_number()
			ui.mark_cell_executed(cell_num)

			-- Save cursor position before evaluating
			local cursor_pos = vim.api.nvim_win_get_cursor(0)

			-- Always evaluate the # %% delimited cell
			-- This works whether or not a Molten cell already exists
			evaluate_percent_cell()

			-- Restore cursor position after evaluation
			vim.defer_fn(function()
				vim.api.nvim_win_set_cursor(0, cursor_pos)
			end, 100)
		end, vim.tbl_extend("force", opts, { desc = "Re-evaluate current cell" }))

		-- Run all cells in the buffer
		vim.keymap.set("n", "<leader>jR", function()
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.b[bufnr].molten_initialized then
				vim.notify("⚠️  No kernel initialized. Press <leader>jl to auto-initialize.", vim.log.levels.WARN)
				return
			end

			-- Save current position
			local save_pos = vim.fn.getpos(".")

			-- Find all cell markers
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local cell_count = 0
			for _, line in ipairs(lines) do
				if line:match("^# %%") then
					cell_count = cell_count + 1
				end
			end

			if cell_count == 0 then
				vim.notify("No cells found in buffer", vim.log.levels.WARN)
				return
			end

			vim.notify(string.format("Running %d cells...", cell_count), vim.log.levels.INFO)

			-- Go to the beginning of the file
			vim.cmd("normal! gg")

			-- Function to run cells sequentially with delay
			local ui = require("pyworks.ui")
			local function run_next_cell(cell_num)
				if cell_num > cell_count then
					-- All cells executed, restore position
					vim.fn.setpos(".", save_pos)
					vim.notify("✓ All cells executed", vim.log.levels.INFO)
					return
				end

				-- Find the Nth cell
				vim.cmd("normal! gg")
				for _ = 1, cell_num do
					vim.fn.search("^# %%", "W")
				end

				-- Mark cell as executed
				ui.mark_cell_executed(cell_num)

				-- Execute the cell
				evaluate_percent_cell()

				-- Schedule next cell execution
				vim.defer_fn(function()
					run_next_cell(cell_num + 1)
				end, 200) -- 200ms delay between cells to avoid overwhelming the kernel
			end

			-- Start running cells
			run_next_cell(1)
		end, vim.tbl_extend("force", opts, { desc = "Run all cells" }))

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

		-- Go to cell N (based on # %% markers, not Molten cells)
		vim.keymap.set("n", "<leader>jg", function()
			vim.ui.input({ prompt = "Go to cell number: " }, function(input)
				if input and input ~= "" then
					local cell_num = tonumber(input)
					if cell_num and cell_num > 0 then
						-- Save current position
						local save_pos = vim.fn.getpos(".")

						-- Go to beginning of file
						vim.cmd("normal! gg")

						-- Search for the Nth cell marker
						local cells_found = 0
						for i = 1, cell_num do
							local result = vim.fn.search("^# %%", "W")
							if result == 0 then
								-- Not enough cells, restore position
								vim.fn.setpos(".", save_pos)
								if cells_found == 0 then
									vim.notify("No cells found in this file", vim.log.levels.WARN)
								else
									vim.notify(
										string.format("Cell %d not found (only %d cells exist)", cell_num, cells_found),
										vim.log.levels.WARN
									)
								end
								return
							end
							cells_found = i
						end

						-- Move to the line after the cell marker
						vim.cmd("normal! j")
						vim.notify("Jumped to cell " .. cell_num, vim.log.levels.INFO)
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
			-- Silently try to delete - if not in cell, no error shown
			pcall(vim.cmd, "silent! MoltenDelete")
		end, vim.tbl_extend("force", opts, { desc = "Delete cell output" }))

		-- Hide output window
		vim.keymap.set("n", "<leader>jh", function()
			-- Try to hide current Molten cell output if it exists
			local ok = pcall(vim.cmd, "MoltenHideOutput")
			if not ok then
				vim.notify("No output window to hide", vim.log.levels.INFO)
			end
		end, vim.tbl_extend("force", opts, { desc = "Hide output window" }))

		-- Enter/open output window
		vim.keymap.set("n", "<leader>jo", function()
			-- Silently try to enter output - if not in cell, no error shown
			pcall(vim.cmd, "silent! noautocmd MoltenEnterOutput")
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

			-- Check if it's a markdown cell (matches "# %% [markdown]" or "# %%[markdown]")
			if line:match("%[markdown%]") then
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

		-- ============================================================================
		-- CELL FOLDING & UI
		-- ============================================================================

		-- Toggle cell folding
		vim.keymap.set("n", "<leader>jf", function()
			local ui = require("pyworks.ui")
			ui.toggle_cell_folding()
		end, vim.tbl_extend("force", opts, { desc = "Toggle cell folding" }))

		-- Collapse all cells
		vim.keymap.set("n", "<leader>jzc", function()
			local ui = require("pyworks.ui")
			ui.collapse_all_cells()
		end, vim.tbl_extend("force", opts, { desc = "Collapse all cells" }))

		-- Expand all cells
		vim.keymap.set("n", "<leader>jze", function()
			local ui = require("pyworks.ui")
			ui.expand_all_cells()
		end, vim.tbl_extend("force", opts, { desc = "Expand all cells" }))

		-- Renumber cells (refresh cell numbers)
		vim.keymap.set("n", "<leader>jn", function()
			local ui = require("pyworks.ui")
			ui.number_cells()
			vim.notify("Cell numbers refreshed", vim.log.levels.INFO)
		end, vim.tbl_extend("force", opts, { desc = "Refresh cell numbers" }))
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
		-- Search for next cell marker (# %% for Python notebooks)
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
