-- pyworks.nvim - Cell Navigation module
-- Navigation for Python files with # %% markers

local M = {}

-- Function to jump to next/previous cell marker
local function jump_to_cell(direction)
	local pattern = "^# %%"
	local flags = direction == "next" and "W" or "bW"

	-- Save current position
	local current_pos = vim.api.nvim_win_get_cursor(0)

	-- Search for pattern
	local result = vim.fn.search(pattern, flags)

	if result == 0 then
		-- No match found, restore position
		vim.api.nvim_win_set_cursor(0, current_pos)
		vim.notify("No " .. direction .. " cell found", vim.log.levels.INFO)
	end
end

-- Flash highlight the current cell
local function flash_cell_highlight(start_line, end_line, duration)
	local ns_id = vim.api.nvim_create_namespace("pyworks_cell_flash")

	-- Create highlight
	for line = start_line - 1, end_line - 1 do
		vim.api.nvim_buf_add_highlight(0, ns_id, "Visual", line, 0, -1)
	end

	-- Clear after duration
	vim.defer_fn(function()
		vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)
	end, duration or 150)
end

function M.setup()
	-- Set up keymaps for cell navigation
	vim.keymap.set("n", "]j", function()
		jump_to_cell("next")
	end, { desc = "Next Jupyter # %% cell" })

	vim.keymap.set("n", "[j", function()
		jump_to_cell("previous")
	end, { desc = "Previous Jupyter # %% cell" })

	-- Navigate and run
	vim.keymap.set("n", "<leader>j}", function()
		jump_to_cell("next")
		vim.cmd("MoltenEvaluateOperator")
		vim.api.nvim_feedkeys("j", "n", false)
	end, { desc = "[J]ump to next cell and prepare to run" })

	vim.keymap.set("n", "<leader>j{", function()
		jump_to_cell("previous")
		vim.cmd("MoltenEvaluateOperator")
		vim.api.nvim_feedkeys("j", "n", false)
	end, { desc = "[J]ump to previous cell and prepare to run" })

	-- Visual selection of current cell (between # %% markers)
	vim.keymap.set("n", "vi%", function()
		-- Search backwards for # %% or beginning of file
		local start_pos = vim.fn.search("^# %%", "bcnW")
		if start_pos == 0 then
			start_pos = 1
		else
			start_pos = start_pos + 1
		end

		-- Search forwards for next # %% or end of file
		local end_pos = vim.fn.search("^# %%", "nW")
		if end_pos == 0 then
			end_pos = vim.fn.line("$")
		else
			end_pos = end_pos - 1
		end

		-- Select the range
		vim.cmd("normal! " .. start_pos .. "GV" .. end_pos .. "G")
	end, { desc = "Visual select current cell" })

	-- Select current cell
	vim.keymap.set("n", "<leader>jr", function()
		-- Find cell boundaries
		local start_pos = vim.fn.search("^# %%", "bcnW")
		if start_pos == 0 then
			start_pos = 1
		else
			start_pos = start_pos + 1
		end

		local end_pos = vim.fn.search("^# %%", "nW")
		if end_pos == 0 then
			end_pos = vim.fn.line("$")
		else
			end_pos = end_pos - 1
		end

		-- Check if cell has content
		if end_pos < start_pos then
			vim.notify("Empty cell", vim.log.levels.WARN)
			return
		end

		-- Flash highlight to show what will run
		flash_cell_highlight(start_pos, end_pos, 150)

		-- Move to start of cell
		vim.api.nvim_win_set_cursor(0, { start_pos, 0 })

		-- Select the cell visually
		vim.cmd("normal! V" .. end_pos .. "G")
	end, { desc = "[J]upyter select cu[R]rent cell" })

	vim.keymap.set("n", "<leader>jV", function()
		-- Find cell boundaries
		local start_pos = vim.fn.search("^# %%", "bcnW")
		if start_pos == 0 then
			start_pos = 1
		else
			start_pos = start_pos + 1
		end

		local end_pos = vim.fn.search("^# %%", "nW")
		if end_pos == 0 then
			end_pos = vim.fn.line("$")
		else
			end_pos = end_pos - 1
		end

		-- Select the cell
		vim.cmd("normal! " .. start_pos .. "GV" .. end_pos .. "G")

		-- Notify what will be run
		local lines = end_pos - start_pos + 1
		vim.notify("Selected " .. lines .. " lines. Press <leader>jv to run", vim.log.levels.INFO)
	end, { desc = "[J]upyter [V]isually select current cell" })
end

return M
