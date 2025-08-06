-- pyworks.nvim - Molten integration module
-- Provides better integration with molten-nvim

local M = {}
local utils = require("pyworks.utils")

-- Initialize Molten with better UX
function M.init_kernel(silent_mode)
	-- Start progress indicator
	local progress_id = silent_mode and nil or utils.progress_start("Initializing Jupyter kernel")

	-- Run initialization asynchronously
	vim.schedule(function()
		-- Check if already initialized
		local kernels = vim.fn.MoltenAvailableKernels()

		-- If no kernels available, show error
		if vim.tbl_isempty(kernels or {}) then
			if progress_id then
				utils.progress_end(progress_id, false, "No kernels found")
			end
			if not silent_mode then
				utils.notify("No Jupyter kernels found! Run :PyworksSetup first.", vim.log.levels.ERROR)
			end
			return
		end

		-- If only one kernel (usually python3), just use it
		if #kernels == 1 then
			local kernel = kernels[1]

			-- Initialize asynchronously
			vim.schedule(function()
				local ok = pcall(vim.cmd, "MoltenInit " .. kernel)
				if ok then
					if progress_id then
						utils.progress_end(progress_id, true)
					elseif not silent_mode then
						utils.notify("Kernel ready: " .. kernel, vim.log.levels.INFO, nil, "success")
					end
				else
					if progress_id then
						utils.progress_end(progress_id, false, "Failed to initialize kernel")
					end
				end
			end)
			return
		end

		-- Multiple kernels available, let user choose
		if progress_id then
			utils.progress_end(progress_id, false) -- End progress before showing select
		end

		utils.better_select("Select Jupyter kernel:", kernels, function(selected)
			if selected then
				local init_progress = utils.progress_start("Initializing " .. selected)
				vim.schedule(function()
					local ok = pcall(vim.cmd, "MoltenInit " .. selected)
					if ok then
						utils.progress_end(init_progress, true)
					else
						utils.progress_end(init_progress, false, "Failed to initialize")
					end
				end)
			end
		end)
	end)
end

-- Better cell execution with feedback
function M.evaluate_line()
	-- Save cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)

	-- Execute the command
	vim.cmd("MoltenEvaluateLine")

	-- Restore cursor position safely
	vim.schedule(function()
		if vim.api.nvim_win_is_valid(0) and cursor and #cursor == 2 then
			pcall(vim.api.nvim_win_set_cursor, 0, cursor)
		end
	end)
end

-- Evaluate visual selection
function M.evaluate_visual()
	-- Make sure we're executing from visual mode
	-- The keybinding should be called while still in visual mode
	vim.cmd("MoltenEvaluateVisual")
end

-- Run current cell with visual feedback
function M.run_cell()
	-- First select the cell
	vim.cmd("normal! vi%")
	-- Then evaluate it
	vim.cmd("MoltenEvaluateVisual")
	-- Exit visual mode
	vim.cmd("normal! <Esc>")
end

-- Smart cell navigation that shows cell boundaries
function M.next_cell()
	local ok = pcall(vim.cmd, "MoltenNext")
	if not ok then
		-- Try custom cell navigation
		vim.cmd("normal! ]j")
	end
end

function M.prev_cell()
	local ok = pcall(vim.cmd, "MoltenPrev")
	if not ok then
		-- Try custom cell navigation
		vim.cmd("normal! [j")
	end
end

return M
