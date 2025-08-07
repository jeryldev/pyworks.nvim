-- pyworks.nvim - Molten integration module
-- Provides better integration with molten-nvim

local M = {}
local utils = require("pyworks.utils")

-- Initialize Molten with better UX
function M.init_kernel(silent_mode)
	-- Check if MoltenInit exists
	if vim.fn.exists(":MoltenInit") ~= 2 then
		utils.notify("Jupyter not configured. Run :PyworksSetup and choose 'Data Science / Notebooks'", vim.log.levels.ERROR)
		return
	end
	
	-- Check if we have a virtual environment
	local venv_exists = vim.fn.isdirectory(vim.fn.getcwd() .. "/.venv") == 1
	if not venv_exists then
		utils.notify("No Python environment found!", vim.log.levels.ERROR)
		utils.notify("Run :PyworksSetup and choose 'Data Science / Notebooks' to get started", vim.log.levels.INFO)
		return
	end
	
	-- Check if Jupyter is installed
	local has_jupyter = vim.fn.system("cd " .. vim.fn.getcwd() .. " && .venv/bin/python -c 'import jupyter_client' 2>/dev/null")
	if vim.v.shell_error ~= 0 then
		utils.notify("Jupyter not installed in this environment!", vim.log.levels.ERROR)
		utils.notify("Run :PyworksSetup and choose 'Data Science / Notebooks'", vim.log.levels.INFO)
		return
	end
	
	-- Get list of available kernels
	local kernels_list = vim.fn.system("jupyter kernelspec list --json 2>/dev/null")
	if vim.v.shell_error ~= 0 or not kernels_list then
		utils.notify("No Jupyter kernels found!", vim.log.levels.ERROR)
		utils.notify("Install with: python -m ipykernel install --user", vim.log.levels.INFO)
		return
	end
	
	local ok, kernels_data = pcall(vim.json.decode, kernels_list)
	if not ok or not kernels_data or not kernels_data.kernelspecs then
		-- Fall back to Molten's built-in selection
		vim.cmd("MoltenInit")
		return
	end
	
	-- Build list of available kernels
	local available_kernels = {}
	for kernel_name, kernel_info in pairs(kernels_data.kernelspecs) do
		table.insert(available_kernels, {
			name = kernel_name,
			display = kernel_info.spec and kernel_info.spec.display_name or kernel_name
		})
	end
	
	if #available_kernels == 0 then
		utils.notify("No Jupyter kernels found!", vim.log.levels.ERROR)
		utils.notify("Install with: python -m ipykernel install --user", vim.log.levels.INFO)
		return
	end
	
	-- Detect file type to find matching kernel
	local filetype = vim.bo.filetype
	local filename = vim.fn.expand("%:t")
	local matching_kernel = nil
	
	-- For notebooks, try to detect language from metadata
	local notebook_language = nil
	if filename:match("%.ipynb$") then
		-- Try to get language from notebook metadata
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local content = table.concat(lines, "\n")
		local ok, notebook = pcall(vim.json.decode, content)
		if ok and notebook and notebook.metadata then
			if notebook.metadata.language_info and notebook.metadata.language_info.name then
				notebook_language = notebook.metadata.language_info.name
			elseif notebook.metadata.kernelspec and notebook.metadata.kernelspec.language then
				notebook_language = notebook.metadata.kernelspec.language
			end
		end
		-- Default to Python if no language detected
		notebook_language = notebook_language or "python"
	end
	
	-- Check if it's a notebook or Python file
	if filetype == "python" or notebook_language == "python" then
		-- First, try to find a project-specific kernel
		local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
		
		-- Debug output
		if not silent_mode then
			utils.notify("Looking for kernel matching project: " .. project_name, vim.log.levels.DEBUG)
		end
		
		for _, k in ipairs(available_kernels) do
			-- Prefer project-specific kernels (exact match or contains project name)
			if k.name == project_name or k.name:lower() == project_name:lower() then
				matching_kernel = k.name
				break
			end
		end
		
		-- If no project kernel, fall back to python3
		if not matching_kernel then
			for _, k in ipairs(available_kernels) do
				if k.name == "python3" or k.name:match("^python") then
					matching_kernel = k.name
					break
				end
			end
		end
	elseif filetype == "julia" or notebook_language == "julia" then
		for _, k in ipairs(available_kernels) do
			if k.name:match("^julia") then
				matching_kernel = k.name
				break
			end
		end
	elseif filetype == "r" or notebook_language == "r" then
		for _, k in ipairs(available_kernels) do
			if k.name == "ir" or k.name:match("^ir$") then
				matching_kernel = k.name
				break
			end
		end
	end
	
	-- If we found a matching kernel, auto-initialize it
	if matching_kernel then
		-- Just initialize directly without any fancy stuff
		vim.cmd("MoltenInit " .. matching_kernel)
		if not silent_mode then
			utils.notify("✓ Initialized kernel: " .. matching_kernel, vim.log.levels.INFO)
		end
	else
		-- No matching kernel, show selection dialog
		if not silent_mode then
			M.show_kernel_selection(available_kernels)
		end
	end
end

-- Show kernel selection dialog
function M.show_kernel_selection(kernels)
	local kernel_names = {}
	for _, k in ipairs(kernels) do
		table.insert(kernel_names, k.display .. " (" .. k.name .. ")")
	end
	
	utils.better_select("Select Jupyter kernel:", kernel_names, function(selected)
		if selected then
			-- Extract kernel name from selection
			local kernel_name = selected:match("%((.-)%)$")
			if kernel_name then
				local progress_id = utils.progress_start("Initializing " .. kernel_name)
				vim.schedule(function()
					-- Initialize kernel (don't use shared - it breaks images)
					local ok = pcall(vim.cmd, "MoltenInit " .. kernel_name)
					if ok then
						utils.progress_end(progress_id, true)
						utils.notify("✓ Kernel ready! Use <leader>jl to run lines, <leader>jv for selections", vim.log.levels.INFO)
					else
						utils.progress_end(progress_id, false, "Failed to initialize kernel")
					end
				end)
			end
		end
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
