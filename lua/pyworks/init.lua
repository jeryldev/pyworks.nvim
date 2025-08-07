-- pyworks.nvim - Python environments tailored for Neovim
-- Main module

local M = {}
local config = require("pyworks.config")

-- Setup function
function M.setup(opts)
	-- Setup jupytext metadata fixing
	require("pyworks.jupytext").setup()

	-- Set Python host if not already set
	if not vim.g.python3_host_prog then
		-- Try to find the best Python executable
		local python_candidates = {
			vim.fn.getcwd() .. "/.venv/bin/python3",
			vim.fn.getcwd() .. "/.venv/bin/python",
			vim.fn.exepath("python3"),
			vim.fn.exepath("python"),
		}

		for _, python_path in ipairs(python_candidates) do
			if vim.fn.executable(python_path) == 1 then
				vim.g.python3_host_prog = python_path
				break
			end
		end
	end

	-- Validate and setup configuration
	if opts then
		local ok, errors = config.validate_config(opts)
		if not ok then
			vim.notify("pyworks.nvim: Invalid configuration:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
			return
		end
	end

	-- Setup configuration
	M.config = config.setup(opts)

	-- Load submodules
	require("pyworks.commands").setup()
	require("pyworks.autocmds").setup(M.config)
	require("pyworks.cell-navigation").setup()

	-- Create user commands
	require("pyworks.commands").create_commands()

	-- Set up Molten keymappings (always set them up, they'll check for Molten availability)
	local molten = require("pyworks.molten")

	-- Core Molten keymappings
	vim.keymap.set("n", "<leader>ji", function()
		molten.init_kernel()
	end, { desc = "[J]upyter [I]nitialize kernel" })
	vim.keymap.set("n", "<leader>jl", function()
		if vim.fn.exists(":MoltenEvaluateLine") == 2 then
			-- Check if kernel is running for this buffer
			if vim.fn.exists("*MoltenRunningKernels") == 1 then
				local buffer_kernels = vim.fn.MoltenRunningKernels(true) or {}
				if #buffer_kernels == 0 then
					-- No kernel running, auto-initialize based on file type
					local ft = vim.bo.filetype
					if ft == "python" or ft == "julia" or ft == "r" then
						vim.notify("Auto-initializing kernel...", vim.log.levels.INFO)
						molten.init_kernel(true) -- Silent mode
						-- Wait a bit then run the line
						vim.defer_fn(function()
							molten.evaluate_line()
						end, 500)
						return
					end
				end
			end
			molten.evaluate_line()
		else
			vim.notify("Molten not available. Ensure it's installed.", vim.log.levels.ERROR)
		end
	end, { desc = "[J]upyter evaluate [L]ine" })

	-- Visual mode mapping for running selection (both v and x modes)
	vim.keymap.set(
		{ "v", "x" },
		"<leader>jv",
		":<C-u>MoltenEvaluateVisual<CR>",
		{ desc = "[J]upyter evaluate [V]isual", silent = true }
	)

	-- Also add normal mode mapping that uses the last visual selection
	vim.keymap.set("n", "<leader>jv", function()
		if vim.fn.exists(":MoltenEvaluateVisual") == 2 then
			-- Check if kernel is running for this buffer
			if vim.fn.exists("*MoltenRunningKernels") == 1 then
				local buffer_kernels = vim.fn.MoltenRunningKernels(true) or {}
				if #buffer_kernels == 0 then
					-- No kernel running, auto-initialize based on file type
					local ft = vim.bo.filetype
					if ft == "python" or ft == "julia" or ft == "r" then
						vim.notify("Auto-initializing kernel...", vim.log.levels.INFO)
						molten.init_kernel(true) -- Silent mode
						-- Wait a bit then run the selection
						vim.defer_fn(function()
							vim.cmd("normal! gv")
							vim.cmd("MoltenEvaluateVisual")
						end, 500)
						return
					end
				end
			end
			-- Re-select the last visual selection and run it
			vim.cmd("normal! gv")
			vim.cmd("MoltenEvaluateVisual")
		else
			vim.notify("Molten not available. Ensure it's installed.", vim.log.levels.ERROR)
		end
	end, { desc = "[J]upyter evaluate last [V]isual selection" })

	vim.keymap.set("n", "<leader>je", function()
		if vim.fn.exists(":MoltenEvaluateOperator") == 2 then
			vim.cmd("MoltenEvaluateOperator")
		else
			vim.notify("Jupyter not initialized. Press <leader>ji first", vim.log.levels.WARN)
		end
	end, { desc = "[J]upyter [E]valuate operator" })

	vim.keymap.set("n", "<leader>jo", function()
		if vim.fn.exists(":MoltenEnterOutput") == 2 then
			vim.cmd("noautocmd MoltenEnterOutput")
		else
			vim.notify("Jupyter not initialized. Press <leader>ji first", vim.log.levels.WARN)
		end
	end, { desc = "[J]upyter [O]pen output" })

	vim.keymap.set("n", "<leader>jh", function()
		if vim.fn.exists(":MoltenHideOutput") == 2 then
			vim.cmd("MoltenHideOutput")
		else
			vim.notify("Jupyter not initialized. Press <leader>ji first", vim.log.levels.WARN)
		end
	end, { desc = "[J]upyter [H]ide output" })

	vim.keymap.set("n", "<leader>jd", function()
		if vim.fn.exists(":MoltenDelete") == 2 then
			vim.cmd("MoltenDelete")
		else
			vim.notify("Jupyter not initialized. Press <leader>ji first", vim.log.levels.WARN)
		end
	end, { desc = "[J]upyter [D]elete cell" })

	vim.keymap.set("n", "<leader>js", function()
		if vim.fn.exists(":MoltenInfo") == 2 then
			vim.cmd("MoltenInfo")
		else
			vim.notify("Jupyter not initialized. Press <leader>ji first", vim.log.levels.WARN)
		end
	end, { desc = "[J]upyter [S]tatus/info" })

	-- Image clearing (if image.nvim is available)
	vim.keymap.set("n", "<leader>jc", function()
		local ok, image = pcall(require, "image")
		if ok then
			image.clear()
		else
			vim.notify("Image support not available", vim.log.levels.WARN)
		end
	end, { desc = "[J]upyter [C]lear images" })
	
	-- Package management keybindings
	vim.keymap.set("n", "<leader>pi", function()
		local detector = require("pyworks.package-detector")
		detector.install_suggested()
	end, { desc = "[P]yworks [I]nstall suggested packages" })
	
	vim.keymap.set("n", "<leader>pa", function()
		vim.cmd("PyworksAnalyzeImports")
	end, { desc = "[P]yworks [A]nalyze imports" })

	-- Mark setup as complete
	config.set_state("setup_completed", true)
end

-- Expose config for backward compatibility
function M.get_config()
	return config.current
end

return M
