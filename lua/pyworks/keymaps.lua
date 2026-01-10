-- Keymaps for pyworks.nvim
-- Cell execution with Molten integration for Python:
-- 1. Python files (.py) with python3 kernel
-- 2. Python notebooks (.ipynb) with python3 kernel
-- Uses Molten + image.nvim for execution and display

local M = {}

local detector = require("pyworks.core.detector")
local error_handler = require("pyworks.core.error_handler")
local ui = require("pyworks.ui")

local BUFFER_SETTLE_DELAY_MS = 100
local POLL_INTERVAL_MS = 150 -- How often to check for cell completion
local CELL_TIMEOUT_MS = 30000 -- Maximum wait time per cell (30 seconds)

-- Cache for Molten namespace ID (cleared on buffer change to handle namespace recreation)
local molten_ns_cache = nil

-- Concatenate virtual text parts into a single string
local function concat_virt_text(virt_text)
	local text = ""
	for _, vt in ipairs(virt_text) do
		text = text .. (vt[1] or "")
	end
	return text
end

-- Get Molten namespace ID (cached for performance in hot path)
-- Returns namespace ID or nil if Molten namespace not found
local function get_molten_namespace()
	if molten_ns_cache then
		return molten_ns_cache
	end
	local namespaces = vim.api.nvim_get_namespaces()
	for name, id in pairs(namespaces) do
		if type(name) == "string" and name:match("^molten") then
			molten_ns_cache = id
			return id
		end
	end
	return nil
end

-- Debug: dump all extmarks with virtual text/lines to see actual Molten output format
local function debug_dump_extmarks(bufnr)
	local namespaces = vim.api.nvim_get_namespaces()
	local found_any = false

	for ns_name, ns_id in pairs(namespaces) do
		if type(ns_name) == "string" then
			local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
			for _, mark in ipairs(marks) do
				local details = mark[4]
				-- Check virt_text (text at end of line)
				if details and details.virt_text then
					found_any = true
					local full_text = concat_virt_text(details.virt_text)
					vim.notify(
						string.format("[DEBUG] ns=%s line=%d virt_text='%s'", ns_name, mark[2] + 1, full_text),
						vim.log.levels.INFO
					)
				end
				-- Check virt_lines (entire lines below the actual line)
				if details and details.virt_lines then
					found_any = true
					for line_idx, virt_line in ipairs(details.virt_lines) do
						local line_text = concat_virt_text(virt_line)
						vim.notify(
							string.format(
								"[DEBUG] ns=%s line=%d virt_lines[%d]='%s'",
								ns_name,
								mark[2] + 1,
								line_idx,
								line_text
							),
							vim.log.levels.INFO
						)
					end
				end
			end
		end
	end

	if not found_any then
		vim.notify("[DEBUG] No extmarks with virtual text/lines found in any namespace", vim.log.levels.INFO)
	end
end

-- Check if text contains completed output pattern and extract the number
-- Returns the Out[N] number if completed, nil otherwise
local function extract_completed_output_num(text)
	local num = text:match("Out%[(%d+)%]")
	if num and (text:match("✓") or text:match("Done")) then
		return tonumber(num)
	end
	return nil
end

-- Find the highest completed Out[N] number in the buffer's virtual text/lines
-- Looks for "Out[N]: ✓ Done" pattern which indicates cell execution completed
-- Optimized: Only checks Molten namespace (not LSP diagnostics etc.)
-- Returns the highest completed number found, or 0 if none
local function get_highest_completed_output(bufnr)
	local highest = 0

	-- Only check Molten namespace for performance (skip LSP diagnostics etc.)
	local ns_id = get_molten_namespace()
	if not ns_id then
		return 0
	end

	local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
	for _, mark in ipairs(marks) do
		local details = mark[4]

		-- Check virt_text (text at end of line)
		if details and details.virt_text then
			local full_text = concat_virt_text(details.virt_text)
			local n = extract_completed_output_num(full_text)
			if n and n > highest then
				highest = n
			end
		end

		-- Check virt_lines (entire virtual lines below the actual line)
		-- This is what Molten uses for output display
		if details and details.virt_lines then
			for _, virt_line in ipairs(details.virt_lines) do
				local line_text = concat_virt_text(virt_line)
				local n = extract_completed_output_num(line_text)
				if n and n > highest then
					highest = n
				end
			end
		end
	end

	return highest
end

-- Wait for cell execution to complete by monitoring Out[N] ✓ Done pattern
-- Calls callback(success) when a new completed output appears or timeout
local function wait_for_cell_completion(bufnr, callback)
	local start_time = vim.uv.now()
	local initial_completed = get_highest_completed_output(bufnr)

	-- Debug: log initial state and dump extmarks
	if vim.g.pyworks_debug then
		vim.notify(
			string.format("[DEBUG] wait_for_cell_completion: initial_completed=%d", initial_completed),
			vim.log.levels.DEBUG
		)
		debug_dump_extmarks(bufnr)
	end

	local timer = vim.uv.new_timer()
	timer:start(
		POLL_INTERVAL_MS,
		POLL_INTERVAL_MS,
		vim.schedule_wrap(function()
			-- Check timeout
			if vim.uv.now() - start_time > CELL_TIMEOUT_MS then
				timer:stop()
				timer:close()
				-- Debug: dump extmarks on timeout to see what we missed
				if vim.g.pyworks_debug then
					vim.notify("[DEBUG] Timeout reached, dumping extmarks:", vim.log.levels.DEBUG)
					debug_dump_extmarks(bufnr)
				end
				callback(false, "timeout")
				return
			end

			-- Check if buffer is still valid
			if not vim.api.nvim_buf_is_valid(bufnr) then
				timer:stop()
				timer:close()
				callback(false, "buffer_invalid")
				return
			end

			-- Check if a new Out[N] ✓ Done appeared (completion indicator)
			local current_completed = get_highest_completed_output(bufnr)
			if current_completed > initial_completed then
				timer:stop()
				timer:close()
				if vim.g.pyworks_debug then
					vim.notify(
						string.format("[DEBUG] Cell completed! Out[%d] detected", current_completed),
						vim.log.levels.DEBUG
					)
				end
				callback(true)
				return
			end
		end)
	)
end

-- Check if current cell is a markdown cell (no executable code)
local function is_markdown_cell()
	local cell_start = vim.fn.search("^# %%", "bnW")
	if cell_start == 0 then
		return false
	end
	local line = vim.fn.getline(cell_start)
	return line:match("%[markdown%]") ~= nil
end

-- Suppress Molten events during navigation (workaround for Molten extmark bug)
local function with_suppressed_events(fn)
	local saved = vim.o.eventignore
	vim.o.eventignore = "CursorMoved,CursorMovedI,WinScrolled"
	local ok, err = pcall(fn)
	vim.o.eventignore = saved
	if not ok then
		error(err)
	end
end

-- Helper function to find and execute code between # %% markers
-- This creates a Molten cell if one doesn't exist yet
-- Returns start_line, end_line of the executed cell (or nil if empty/error)
local function evaluate_percent_cell()
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
		return nil, nil
	end

	-- Use MoltenEvaluateRange function (more reliable than visual mode simulation)
	-- This is a Vim function exposed by Molten, not a command
	local ok = pcall(vim.fn.MoltenEvaluateRange, start_line, end_line)
	if not ok then
		-- Fallback: set visual marks and run MoltenEvaluateVisual
		vim.fn.setpos("'<", { 0, start_line, 1, 0 })
		vim.fn.setpos("'>", { 0, end_line, vim.fn.col({ end_line, "$" }) - 1, 0 })
		pcall(vim.cmd, "'<,'>MoltenEvaluateVisual")
	end

	return start_line, end_line
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

		-- Run current line (auto-initializes kernel if needed)
		vim.keymap.set("n", "<leader>jl", function()
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.b[bufnr].molten_initialized then
				local ft = vim.bo.filetype
				local filepath = vim.api.nvim_buf_get_name(bufnr)
				local kernel = detector.get_kernel_for_language(ft, filepath)

				if kernel then
					vim.notify("Initializing " .. kernel .. " kernel...", vim.log.levels.INFO)
					local ok =
						error_handler.protected_call(vim.cmd, "Failed to initialize kernel", "MoltenInit " .. kernel)
					if ok then
						vim.b[bufnr].molten_initialized = true
					end

					-- Defer execution to allow kernel initialization to complete
					vim.defer_fn(function()
						error_handler.protected_call(vim.cmd, "Failed to evaluate line", "MoltenEvaluateLine")
						local cursor = vim.api.nvim_win_get_cursor(0)
						local next_line = cursor[1] + 1
						local last_line = vim.api.nvim_buf_line_count(0)
						if next_line <= last_line then
							vim.api.nvim_win_set_cursor(0, { next_line, cursor[2] })
						end
					end, BUFFER_SETTLE_DELAY_MS)
					return
				end
			end

			pcall(vim.cmd, "MoltenEvaluateLine")

			-- Auto-advance to next line
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

		-- Run current cell and move to next (classic Jupyter Shift+Enter behavior)
		vim.keymap.set("n", "<leader>jj", function()
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.b[bufnr].molten_initialized then
				vim.notify("No kernel initialized. Press <leader>jl to auto-initialize.", vim.log.levels.WARN)
				return
			end

			local cell_num = ui.get_current_cell_number()
			ui.mark_cell_executed(cell_num)

			-- Evaluate # %% delimited cell (works with or without existing Molten cell)
			evaluate_percent_cell()

			-- Defer navigation to allow evaluation to start
			vim.defer_fn(function()
				local found = vim.fn.search("^# %%", "W")
				if found == 0 then
					vim.notify("Last cell", vim.log.levels.INFO)
				else
					ui.enter_cell(found, { insert_mode = false })
				end
			end, BUFFER_SETTLE_DELAY_MS)
		end, vim.tbl_extend("force", opts, { desc = "Run cell and move to next" }))

		-- Run all cells in the buffer sequentially
		vim.keymap.set("n", "<leader>jR", function()
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.b[bufnr].molten_initialized then
				vim.notify("No kernel initialized. Press <leader>jl to auto-initialize.", vim.log.levels.WARN)
				return
			end

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

			with_suppressed_events(function()
				vim.cmd("normal! gg")
			end)

			local function run_next_cell(cell_num)
				if cell_num > cell_count then
					-- Go to last cell and position cursor below the marker
					with_suppressed_events(function()
						vim.cmd("normal! G")
					end)
					local last_cell_line = vim.fn.search("^# %%", "bW")
					if last_cell_line > 0 then
						ui.enter_cell(last_cell_line, { insert_mode = false })
					end
					vim.notify("All cells executed", vim.log.levels.INFO)
					return
				end

				with_suppressed_events(function()
					vim.cmd("normal! gg")
					for _ = 1, cell_num do
						vim.fn.search("^# %%", "W")
					end
				end)

				-- Check if this is a markdown cell (skip execution, no output expected)
				if is_markdown_cell() then
					ui.mark_cell_executed(cell_num)
					vim.defer_fn(function()
						run_next_cell(cell_num + 1)
					end, BUFFER_SETTLE_DELAY_MS)
					return
				end

				ui.mark_cell_executed(cell_num)
				local cell_start, _ = evaluate_percent_cell()

				if cell_start then
					-- Wait for cell execution to complete (Out[N] ✓ Done) before running next cell
					wait_for_cell_completion(bufnr, function(success, reason)
						if not success and reason == "timeout" then
							vim.notify(
								string.format("Cell %d timed out after 30s, continuing...", cell_num),
								vim.log.levels.WARN
							)
						end
						-- Small delay to let output render, then continue
						vim.defer_fn(function()
							run_next_cell(cell_num + 1)
						end, BUFFER_SETTLE_DELAY_MS)
					end)
				else
					-- Empty cell, skip to next
					vim.defer_fn(function()
						run_next_cell(cell_num + 1)
					end, BUFFER_SETTLE_DELAY_MS)
				end
			end

			run_next_cell(1)
		end, vim.tbl_extend("force", opts, { desc = "Run all cells" }))

		-- ============================================================================
		-- CELL SELECTION & NAVIGATION
		-- ============================================================================

		-- Visual select current cell
		vim.keymap.set("n", "<leader>jv", function()
			if vim.bo.filetype == "python" and not vim.g.python3_host_prog then
				vim.notify("Python host not configured. Run :PyworksSetup first", vim.log.levels.WARN)
				return
			end

			local has_cells = vim.fn.search("^# %%", "nw") > 0

			if has_cells then
				local cell_start = vim.fn.search("^# %%", "bnW")
				if cell_start == 0 then
					vim.cmd("normal! gg")
				else
					vim.cmd("normal! " .. cell_start .. "G")
					vim.cmd("normal! j")
				end

				vim.cmd("normal! V")

				local cell_end = vim.fn.search("^# %%", "nW")
				if cell_end == 0 then
					vim.cmd("normal! G")
				else
					vim.cmd("normal! " .. cell_end .. "G")
					vim.cmd("normal! k")
				end
			else
				vim.cmd("normal! ggVG")
				vim.notify("No cell markers found, selected entire file", vim.log.levels.INFO)
			end
		end, vim.tbl_extend("force", opts, { desc = "Visual select current cell" }))

		-- Go to cell N
		vim.keymap.set("n", "<leader>jg", function()
			vim.ui.input({ prompt = "Go to cell number: " }, function(input)
				if input and input ~= "" then
					local cell_num = tonumber(input)
					if cell_num and cell_num > 0 then
						local save_pos = vim.fn.getpos(".")
						vim.cmd("normal! gg")

						local cells_found = 0
						for i = 1, cell_num do
							local result = vim.fn.search("^# %%", "W")
							if result == 0 then
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

		vim.keymap.set("n", "<leader>jd", function()
			local cell_num = ui.get_current_cell_number()
			if cell_num == 0 then
				vim.notify("Not in a cell", vim.log.levels.INFO)
				return
			end
			local ok = pcall(vim.cmd, "MoltenDelete")
			if ok then
				ui.mark_cell_cleared(cell_num)
			else
				vim.notify("No output to delete", vim.log.levels.INFO)
			end
		end, vim.tbl_extend("force", opts, { desc = "Clear cell output" }))

		-- ============================================================================
		-- CELL CREATION
		-- ============================================================================

		vim.keymap.set("n", "<leader>ja", function()
			local cell_start = vim.fn.search("^# %%", "bnW")
			local insert_line = cell_start > 0 and cell_start - 1 or 0
			vim.fn.append(insert_line, { "# %%", "" })
			vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
			vim.cmd("startinsert")
		end, vim.tbl_extend("force", opts, { desc = "Insert code cell above" }))

		vim.keymap.set("n", "<leader>jb", function()
			local cell_end = vim.fn.search("^# %%", "nW")
			local insert_line = cell_end == 0 and vim.fn.line("$") or cell_end - 1
			vim.fn.append(insert_line, { "", "# %%", "" })
			vim.api.nvim_win_set_cursor(0, { insert_line + 3, 0 })
			vim.cmd("startinsert")
		end, vim.tbl_extend("force", opts, { desc = "Insert code cell below" }))

		vim.keymap.set("n", "<leader>jma", function()
			local cell_start = vim.fn.search("^# %%", "bnW")
			local insert_line = cell_start > 0 and cell_start - 1 or 0
			vim.fn.append(insert_line, { "# %% [markdown]", "# " })
			vim.api.nvim_win_set_cursor(0, { insert_line + 2, 2 })
			vim.cmd("startinsert!")
		end, vim.tbl_extend("force", opts, { desc = "Insert markdown cell above" }))

		vim.keymap.set("n", "<leader>jmb", function()
			local cell_end = vim.fn.search("^# %%", "nW")
			local insert_line = cell_end == 0 and vim.fn.line("$") or cell_end - 1
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
			local new_line, msg
			if line:match("%[markdown%]") then
				new_line = "# %%"
				msg = "Converted to code cell"
			else
				new_line = "# %% [markdown]"
				msg = "Converted to markdown cell"
			end
			vim.fn.setline(cell_start, new_line)
			vim.notify(msg, vim.log.levels.INFO)
		end, vim.tbl_extend("force", opts, { desc = "Toggle cell type" }))

		vim.keymap.set("n", "<leader>jJ", function()
			local next_cell = vim.fn.search("^# %%", "nW")
			if next_cell == 0 then
				vim.notify("No cell below to merge", vim.log.levels.WARN)
				return
			end
			vim.fn.deletebufline("%", next_cell)
			vim.notify("Merged with cell below", vim.log.levels.INFO)
		end, vim.tbl_extend("force", opts, { desc = "Merge with cell below" }))

		vim.keymap.set("n", "<leader>js", function()
			local cursor_line = vim.fn.line(".")
			vim.fn.append(cursor_line, { "", "# %%", "" })
			vim.api.nvim_win_set_cursor(0, { cursor_line + 3, 0 })
			vim.notify("Cell split", vim.log.levels.INFO)
		end, vim.tbl_extend("force", opts, { desc = "Split cell at cursor" }))

		-- ============================================================================
		-- CELL FOLDING & UI
		-- ============================================================================

		vim.keymap.set("n", "<leader>jf", function()
			ui.toggle_cell_folding()
		end, vim.tbl_extend("force", opts, { desc = "Toggle cell folding" }))

		vim.keymap.set("n", "<leader>jc", function()
			ui.collapse_cell()
		end, vim.tbl_extend("force", opts, { desc = "Collapse current cell" }))

		vim.keymap.set("n", "<leader>jC", function()
			ui.collapse_all_cells()
		end, vim.tbl_extend("force", opts, { desc = "Collapse all cells" }))

		vim.keymap.set("n", "<leader>je", function()
			ui.expand_cell()
		end, vim.tbl_extend("force", opts, { desc = "Expand current cell" }))

		vim.keymap.set("n", "<leader>jE", function()
			ui.expand_all_cells()
		end, vim.tbl_extend("force", opts, { desc = "Expand all cells" }))

		vim.keymap.set("n", "<leader>jn", function()
			ui.number_cells()
			vim.notify("Cell numbers refreshed", vim.log.levels.INFO)
		end, vim.tbl_extend("force", opts, { desc = "Refresh cell numbers" }))
	else
		-- Fallback keymaps when Molten is not available (select text for manual copying)

		vim.keymap.set("n", "<leader>jv", function()
			-- Use pcall to handle E486 (pattern not found) gracefully
			local ok = pcall(function()
				vim.cmd("normal! ?^# %%\\|^```\\|^```{<CR>")
				vim.cmd("normal! V")
				vim.cmd("normal! /^# %%\\|^```\\|^```{<CR>")
				vim.cmd("normal! k")
			end)
			if ok then
				vim.notify("Molten not available. Cell selected for manual copy.", vim.log.levels.WARN)
			else
				vim.notify("No cell markers found", vim.log.levels.INFO)
			end
		end, vim.tbl_extend("force", opts, { desc = "Select current cell (Molten not available)" }))

		vim.keymap.set("v", "<leader>jr", function()
			vim.notify("Molten not available. Copy selection to run elsewhere.", vim.log.levels.WARN)
		end, vim.tbl_extend("force", opts, { desc = "Run selection (Molten not available)" }))

		vim.keymap.set("n", "<leader>jl", function()
			vim.notify("Molten not available. Use :MoltenInit to initialize.", vim.log.levels.WARN)
		end, vim.tbl_extend("force", opts, { desc = "Run current line (Molten not available)" }))
	end

	-- Cell navigation (works with or without Molten)
	-- Positions cursor on the first content line below the cell marker (stays in normal mode)
	local nav_opts = { insert_mode = false }

	vim.keymap.set("n", "<leader>j]", function()
		local found = vim.fn.search("^# %%", "W")
		if found == 0 then
			vim.notify("No more cells", vim.log.levels.INFO)
		else
			ui.enter_cell(found, nav_opts)
		end
	end, vim.tbl_extend("force", opts, { desc = "Next cell" }))

	vim.keymap.set("n", "<leader>j[", function()
		local current_line = vim.fn.line(".")

		-- First, check if we're on or right after a marker
		local current_marker = vim.fn.search("^# %%", "bcnW")

		-- Search backward for a marker
		local found = vim.fn.search("^# %%", "bW")

		if found == 0 then
			ui.enter_first_cell(nav_opts)
		elseif found == current_marker and current_line <= current_marker + 1 then
			-- We were at or just below a marker, search again for the previous one
			local prev_found = vim.fn.search("^# %%", "bW")
			if prev_found == 0 then
				ui.enter_first_cell(nav_opts)
			else
				ui.enter_cell(prev_found, nav_opts)
			end
		else
			ui.enter_cell(found, nav_opts)
		end
	end, vim.tbl_extend("force", opts, { desc = "Previous cell" }))
end

-- Set up Molten kernel management keymaps
function M.setup_molten_keymaps()
	local opts = { buffer = true, silent = true }
	local has_molten = vim.fn.exists(":MoltenInit") == 2

	if has_molten then
		vim.keymap.set("n", "<leader>mi", function()
			vim.ui.input({ prompt = "Kernel name: " }, function(input)
				if input and input ~= "" then
					vim.cmd("MoltenInit " .. input)
				end
			end)
		end, vim.tbl_extend("force", opts, { desc = "Initialize kernel" }))

		vim.keymap.set("n", "<leader>mr", function()
			local ok = pcall(vim.cmd, "MoltenRestart")
			if not ok then
				vim.notify("No kernel to restart. Initialize with <leader>mi first.", vim.log.levels.WARN)
			end
		end, vim.tbl_extend("force", opts, { desc = "Restart kernel" }))

		vim.keymap.set("n", "<leader>mx", function()
			local ok = pcall(vim.cmd, "MoltenInterrupt")
			if not ok then
				vim.notify("No kernel to interrupt. Initialize with <leader>mi first.", vim.log.levels.WARN)
			end
		end, vim.tbl_extend("force", opts, { desc = "Interrupt execution" }))

		vim.keymap.set("n", "<leader>mI", function()
			local ok = pcall(vim.cmd, "MoltenInfo")
			if not ok then
				vim.notify("No kernel info available. Initialize with <leader>mi first.", vim.log.levels.WARN)
			end
		end, vim.tbl_extend("force", opts, { desc = "Show kernel info" }))
	end
end

-- Export internal functions for testing
M._get_highest_completed_output = get_highest_completed_output
M._is_markdown_cell = is_markdown_cell
M._wait_for_cell_completion = wait_for_cell_completion
M._debug_dump_extmarks = debug_dump_extmarks

-- Debug command: dump all extmarks to see Molten's output format
-- Only available when vim.g.pyworks_debug is set
if vim.g.pyworks_debug then
	vim.api.nvim_create_user_command("PyworksDebugExtmarks", function()
		local bufnr = vim.api.nvim_get_current_buf()
		vim.notify("[DEBUG] Dumping all extmarks with virtual text:", vim.log.levels.INFO)
		debug_dump_extmarks(bufnr)
		local highest = get_highest_completed_output(bufnr)
		vim.notify(string.format("[DEBUG] Highest completed output: Out[%d]", highest), vim.log.levels.INFO)
	end, { desc = "Debug: dump all extmarks to see Molten output format" })
end

return M
