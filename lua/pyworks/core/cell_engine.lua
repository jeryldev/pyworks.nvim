local M = {}

local ui = require("pyworks.ui")

local config = {
	cell_marker = "# %%",
}

function M.configure(opts)
	vim.validate({ opts = { opts, "table", true } })
	config = vim.tbl_deep_extend("force", config, opts or {})
end

function M.get_cell_pattern()
	return "^" .. vim.pesc(config.cell_marker)
end

-- Vim-regex pattern for use with vim.fn.search(). Exported so keymaps.lua
-- can use the configured marker instead of hardcoding "^# %%".
function M.vim_search_pattern()
	return "^" .. config.cell_marker
end

-- Keep the local alias for internal use.
local function vim_search_pattern()
	return M.vim_search_pattern()
end

function M.find_cell_boundaries()
	local pattern = vim_search_pattern()
	local cell_start = vim.fn.search(pattern, "bcnW")
	local cell_end = vim.fn.search(pattern, "nW")

	local start_line, end_line

	if cell_start == 0 and cell_end == 0 then
		start_line = 1
		end_line = vim.fn.line("$")
	elseif cell_start == 0 then
		start_line = 1
		end_line = cell_end - 1
	elseif cell_end == 0 then
		start_line = cell_start + 1
		end_line = vim.fn.line("$")
	else
		start_line = cell_start + 1
		end_line = cell_end - 1
	end

	if start_line > end_line then
		return nil, nil
	end

	return start_line, end_line
end

function M.count_cells(bufnr)
	vim.validate({ bufnr = { bufnr, "number", true } })
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local pattern = M.get_cell_pattern()
	local count = 0
	for _, line in ipairs(lines) do
		if line:match(pattern) then
			count = count + 1
		end
	end
	return count
end

function M.get_cell_positions(bufnr)
	vim.validate({ bufnr = { bufnr, "number", true } })
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local pattern = M.get_cell_pattern()
	local positions = {}
	for i, line in ipairs(lines) do
		if line:match(pattern) then
			table.insert(positions, i)
		end
	end
	return positions
end

function M.is_markdown_cell()
	local pattern = vim_search_pattern()
	local cell_start = vim.fn.search(pattern, "bcnW")
	if cell_start == 0 then
		return false
	end
	local line = vim.fn.getline(cell_start)
	return line:match("%[markdown%]") ~= nil
end

function M.next_cell()
	local pattern = vim_search_pattern()
	local next_marker = vim.fn.search(pattern, "nW")
	if next_marker == 0 then
		return false
	end
	ui.enter_cell(next_marker, { insert_mode = false })
	return true
end

function M.prev_cell()
	local pattern = vim_search_pattern()
	local current_marker = vim.fn.search(pattern, "bcnW")
	if current_marker == 0 then
		return false
	end
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	vim.api.nvim_win_set_cursor(0, { current_marker, 0 })
	local prev_marker = vim.fn.search(pattern, "bnW")
	if prev_marker == 0 or prev_marker == current_marker then
		vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
		return false
	end
	ui.enter_cell(prev_marker, { insert_mode = false })
	return true
end

function M.insert_cell_above()
	local pattern = vim_search_pattern()
	local current_marker = vim.fn.search(pattern, "bcnW")
	local insert_line
	if current_marker == 0 then
		insert_line = 0
	else
		insert_line = current_marker - 1
	end
	vim.fn.append(insert_line, { config.cell_marker, "" })
	ui.enter_cell(insert_line + 1, { insert_mode = false })
end

function M.insert_cell_below()
	local pattern = vim_search_pattern()
	local next_marker = vim.fn.search(pattern, "nW")
	local insert_line
	if next_marker == 0 then
		insert_line = vim.fn.line("$")
	else
		insert_line = next_marker - 1
	end
	vim.fn.append(insert_line, { config.cell_marker, "" })
	ui.enter_cell(insert_line + 1, { insert_mode = false })
end

function M.insert_markdown_above()
	local pattern = vim_search_pattern()
	local current_marker = vim.fn.search(pattern, "bcnW")
	local insert_line
	if current_marker == 0 then
		insert_line = 0
	else
		insert_line = current_marker - 1
	end
	vim.fn.append(insert_line, { config.cell_marker .. " [markdown]", "" })
	ui.enter_cell(insert_line + 1, { insert_mode = false })
end

function M.insert_markdown_below()
	local pattern = vim_search_pattern()
	local next_marker = vim.fn.search(pattern, "nW")
	local insert_line
	if next_marker == 0 then
		insert_line = vim.fn.line("$")
	else
		insert_line = next_marker - 1
	end
	vim.fn.append(insert_line, { config.cell_marker .. " [markdown]", "" })
	ui.enter_cell(insert_line + 1, { insert_mode = false })
end

function M.toggle_cell_type()
	local pattern = vim_search_pattern()
	local cell_start = vim.fn.search(pattern, "bcnW")
	if cell_start == 0 then
		return false
	end
	local line = vim.fn.getline(cell_start)
	local new_line
	if line:match("%[markdown%]") then
		new_line = config.cell_marker
	else
		new_line = config.cell_marker .. " [markdown]"
	end
	vim.api.nvim_buf_set_lines(0, cell_start - 1, cell_start, false, { new_line })
	return true
end

function M.merge_cell_below()
	local pattern = vim_search_pattern()
	local next_marker = vim.fn.search(pattern, "nW")
	if next_marker == 0 then
		return false
	end
	vim.api.nvim_buf_set_lines(0, next_marker - 1, next_marker, false, {})
	return true
end

function M.split_cell()
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	vim.fn.append(cursor_line - 1, { config.cell_marker })
end

-- Execute the current # %% cell via Molten.
-- opts.advance = true moves the cursor to the next cell after dispatching
-- (matches the classic Jupyter Shift+Enter behavior).
-- Returns true on success, false if there is no initialized kernel or the
-- cell is empty.
function M.run_cell(opts)
	vim.validate({ opts = { opts, "table", true } })
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()

	if not vim.b[bufnr].molten_initialized then
		vim.notify("No kernel initialized. Run :PyworksSetup or press <leader>jl first.", vim.log.levels.WARN)
		return false
	end

	local start_line, end_line = M.find_cell_boundaries()
	if not start_line then
		vim.notify("Empty cell", vim.log.levels.WARN)
		return false
	end

	local cell_num = ui.get_current_cell_number()
	ui.mark_cell_executed(cell_num)

	local ok = pcall(vim.fn.MoltenEvaluateRange, start_line, end_line)
	if not ok then
		vim.fn.setpos("'<", { 0, start_line, 1, 0 })
		vim.fn.setpos("'>", { 0, end_line, vim.fn.col({ end_line, "$" }) - 1, 0 })
		pcall(vim.cmd, "'<,'>MoltenEvaluateVisual")
	end

	if opts.advance then
		vim.defer_fn(function()
			local found = vim.fn.search(vim_search_pattern(), "W")
			if found == 0 then
				vim.notify("Last cell", vim.log.levels.INFO)
			else
				ui.enter_cell(found, { insert_mode = false })
			end
		end, 100)
	end

	return true
end

return M
