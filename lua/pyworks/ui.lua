-- UI enhancements for pyworks.nvim
-- Cell highlighting, numbering, and folding

local M = {}

-- Setup cell highlighting with custom highlights
-- Auto-detects light/dark mode and uses appropriate Kanagawa colors
function M.setup_cell_highlights()
	-- Detect if background is light or dark
	local is_light = vim.o.background == "light"

	if is_light then
		-- Kanagawa light mode colors: darker colors for visibility on light background
		vim.api.nvim_set_hl(0, "PyworksCellNumberUnrun", { fg = "#C64343", bold = true }) -- Dark red
		vim.api.nvim_set_hl(0, "PyworksCellNumberExecuted", { fg = "#76946A", bold = true }) -- Dark green
	else
		-- Kanagawa dark mode colors: lighter colors for visibility on dark background
		vim.api.nvim_set_hl(0, "PyworksCellNumberUnrun", { fg = "#E82424", bold = true }) -- Bright red (samuraiRed)
		vim.api.nvim_set_hl(0, "PyworksCellNumberExecuted", { fg = "#98BB6C", bold = true }) -- Bright green (springGreen)
	end
end

-- Track executed cells per buffer
M.executed_cells = {}

-- Namespace for cell numbering (cached)
local cell_numbers_ns = nil

-- Clean up executed_cells when buffer is deleted
-- Use augroup to prevent duplicate autocmds on module reload
local cleanup_augroup = vim.api.nvim_create_augroup("PyworksExecutedCellsCleanup", { clear = true })
vim.api.nvim_create_autocmd("BufDelete", {
	group = cleanup_augroup,
	callback = function(ev)
		M.executed_cells[ev.buf] = nil
	end,
})

-- Mark a cell as executed (green)
function M.mark_cell_executed(cell_num)
	local bufnr = vim.api.nvim_get_current_buf()
	if not M.executed_cells[bufnr] then
		M.executed_cells[bufnr] = {}
	end
	M.executed_cells[bufnr][cell_num] = true
	-- Refresh cell numbers to update colors
	M.number_cells()
end

-- Mark a cell as cleared/unexecuted (red)
function M.mark_cell_cleared(cell_num)
	local bufnr = vim.api.nvim_get_current_buf()
	if M.executed_cells[bufnr] then
		M.executed_cells[bufnr][cell_num] = nil
	end
	-- Refresh cell numbers to update colors
	M.number_cells()
end

-- Get current cell number (for marking as executed)
function M.get_current_cell_number()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor_pos[1]

	-- Count cells up to cursor position
	local lines = vim.api.nvim_buf_get_lines(0, 0, current_line, false)
	local cell_num = 0
	for _, line in ipairs(lines) do
		if line:match("^# %%") then
			cell_num = cell_num + 1
		end
	end
	return cell_num
end

-- Add virtual text numbering to cells with execution status
function M.number_cells()
	local bufnr = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Get or create namespace (cached for performance)
	if not cell_numbers_ns then
		cell_numbers_ns = vim.api.nvim_create_namespace("pyworks_cell_numbers")
	end

	-- Clear existing virtual text from pyworks
	vim.api.nvim_buf_clear_namespace(bufnr, cell_numbers_ns, 0, -1)

	-- Get executed cells for this buffer
	local executed = M.executed_cells[bufnr] or {}

	-- Find and number all cells
	local cell_num = 1
	for i, line in ipairs(lines) do
		if line:match("^# %%") then
			local is_markdown = line:match("%[markdown%]")
			local cell_type = is_markdown and "markdown" or "code"

			-- Use green if executed, red if not
			local hl_group = executed[cell_num] and "PyworksCellNumberExecuted" or "PyworksCellNumberUnrun"
			local virt_text = { { string.format(" [Cell %d: %s]", cell_num, cell_type), hl_group } }

			vim.api.nvim_buf_set_extmark(bufnr, cell_numbers_ns, i - 1, 0, {
				virt_text = virt_text,
				virt_text_pos = "eol",
			})

			cell_num = cell_num + 1
		end
	end
end

-- Setup cell folding based on # %% markers
function M.setup_cell_folding()
	-- Only set up folding if it's not already configured
	local foldexpr = vim.wo.foldexpr or ""
	if vim.wo.foldmethod == "expr" and foldexpr:match("pyworks") then
		return
	end

	-- Set fold method to expr
	vim.wo.foldmethod = "expr"
	vim.wo.foldexpr = "v:lua.require('pyworks.ui').cell_fold_expr()"

	-- Optional: set fold level (0 = all closed, 99 = all open)
	vim.wo.foldlevel = 99 -- Start with all cells expanded

	-- Configure fold text to show cell info
	vim.wo.foldtext = "v:lua.require('pyworks.ui').cell_fold_text()"
end

-- Fold expression for cells
function M.cell_fold_expr()
	local line = vim.fn.getline(vim.v.lnum)

	-- Start a new fold at each cell marker
	if line:match("^# %%") then
		return ">1"
	end

	-- Continue the fold
	return "="
end

-- Custom fold text showing cell info
function M.cell_fold_text()
	local foldstart = vim.v.foldstart
	local foldend = vim.v.foldend
	local line = vim.fn.getline(foldstart)

	-- Determine cell type
	local cell_type = line:match("%[markdown%]") and "Markdown" or "Code"

	-- Count lines in fold
	local line_count = foldend - foldstart + 1

	-- Get first non-marker line for preview
	local preview = ""
	for i = foldstart + 1, math.min(foldstart + 3, foldend) do
		local preview_line = vim.fn.getline(i):gsub("^%s*", ""):gsub("^# ", "")
		if preview_line ~= "" then
			preview = preview_line
			break
		end
	end

	if preview == "" then
		preview = "Empty cell"
	end

	-- Truncate preview if too long
	if #preview > 60 then
		preview = preview:sub(1, 57) .. "..."
	end

	return string.format("  %s Cell (%d lines): %s", cell_type, line_count, preview)
end

-- Toggle cell folding on/off
function M.toggle_cell_folding()
	local foldexpr = vim.wo.foldexpr or ""
	if vim.wo.foldmethod == "expr" and foldexpr:match("pyworks") then
		vim.wo.foldmethod = "manual"
		pcall(vim.cmd, "normal! zE") -- Eliminate all folds (pcall in case no folds exist)
		vim.notify("Cell folding disabled", vim.log.levels.INFO)
	else
		M.setup_cell_folding()
		vim.notify("Cell folding enabled", vim.log.levels.INFO)
	end
end

-- Collapse current cell
function M.collapse_cell()
	M.setup_cell_folding()
	local ok = pcall(vim.cmd, "normal! zc")
	if not ok then
		vim.notify("No cell fold found at cursor position", vim.log.levels.INFO)
	end
end

-- Collapse all cells
function M.collapse_all_cells()
	M.setup_cell_folding()
	local ok = pcall(vim.cmd, "normal! zM")
	if ok then
		vim.notify("All cells collapsed", vim.log.levels.INFO)
	else
		vim.notify("No cells to collapse", vim.log.levels.INFO)
	end
end

-- Expand current cell
function M.expand_cell()
	M.setup_cell_folding()
	local ok = pcall(vim.cmd, "normal! zo")
	if not ok then
		vim.notify("No cell fold found at cursor position", vim.log.levels.INFO)
	end
end

-- Expand all cells
function M.expand_all_cells()
	M.setup_cell_folding()
	local ok = pcall(vim.cmd, "normal! zR")
	if ok then
		vim.notify("All cells expanded", vim.log.levels.INFO)
	else
		vim.notify("No cells to expand", vim.log.levels.INFO)
	end
end

-- Setup UI enhancements for a buffer
function M.setup_buffer(opts)
	opts = opts or {}

	-- Setup highlights
	M.setup_cell_highlights()

	-- Setup cell numbering if enabled
	if opts.show_cell_numbers ~= false then
		M.number_cells()

		-- Re-number cells on buffer changes (buffer-specific augroup)
		local bufnr = vim.api.nvim_get_current_buf()
		local augroup_name = "PyworksCellNumbering_" .. bufnr
		local augroup = vim.api.nvim_create_augroup(augroup_name, { clear = true })
		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufEnter" }, {
			group = augroup,
			buffer = bufnr,
			callback = M.number_cells,
		})
	end

	-- Setup cell folding if enabled
	if opts.enable_cell_folding then
		M.setup_cell_folding()
	end

	-- Note: We don't override syntax highlighting for # %% markers
	-- since # is a comment character and will use the colorscheme's comment color
end

-- Find the line number of the first cell marker (# %%)
-- Returns nil if no cell marker found
-- Does not move cursor - uses buffer inspection
function M.find_first_cell()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	for i, line in ipairs(lines) do
		if line:match("^# %%") then
			return i
		end
	end
	return nil
end

-- Move cursor below a cell marker
-- If marker is at end of file, adds an empty line first
-- @param marker_line: Line number of the cell marker
-- @param opts: Optional table with { insert_mode = true/false } (default: true)
function M.enter_cell(marker_line, opts)
	opts = opts or {}
	local insert_mode = opts.insert_mode ~= false

	local last_line = vim.api.nvim_buf_line_count(0)
	local next_line = marker_line + 1

	-- If marker is at or past the last line, add an empty line below
	if next_line > last_line then
		vim.fn.append(marker_line, "")
	end

	vim.api.nvim_win_set_cursor(0, { next_line, 0 })
	if insert_mode then
		vim.cmd("startinsert")
	end
end

-- Go to the first cell and position cursor on the line below the marker
-- @param opts: Optional table with { insert_mode = true/false } (default: true)
function M.enter_first_cell(opts)
	opts = opts or {}
	local insert_mode = opts.insert_mode ~= false

	local marker_line = M.find_first_cell()
	if marker_line then
		M.enter_cell(marker_line, opts)
	else
		-- No cell marker, just go to line 1
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		if insert_mode then
			vim.cmd("startinsert")
		end
	end
end

-- Create a centered floating window with content
-- @param title: Window title (string)
-- @param content: Array of lines to display
-- @param opts: Optional settings { width = 100, height = auto }
-- @return buf, win: Buffer and window handles
function M.create_floating_window(title, content, opts)
	opts = opts or {}

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false

	-- Calculate window size
	local width = opts.width or 100
	local height = opts.height or #content
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- Open floating window
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = title,
		title_pos = "center",
	})

	-- Close on q or Escape
	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })

	-- Close when leaving window
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = buf,
		once = true,
		callback = close,
	})

	return buf, win
end

return M
