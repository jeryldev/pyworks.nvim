-- Handle .ipynb files with jupytext CLI
-- This runs when pyworks.nvim loads as a plugin

-- Our handler for notebooks
vim.api.nvim_create_autocmd("BufReadCmd", {
	pattern = "*.ipynb",
	group = vim.api.nvim_create_augroup("PyworksNotebooks", { clear = true }),
	callback = function(args)
		local filepath = args.file
		local bufnr = args.buf
		
		-- Set noswapfile to avoid E325 errors
		vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
		
		-- Check if jupytext is available
		local jupytext_available = vim.fn.executable("jupytext") == 1
		if not jupytext_available then
			-- Try to find jupytext in current venv
			local cwd = vim.fn.getcwd()
			local venv_jupytext = cwd .. "/.venv/bin/jupytext"
			if vim.fn.executable(venv_jupytext) == 1 then
				jupytext_available = true
			end
		end
		
		if not jupytext_available then
			vim.notify("Jupytext not found. Install with: pip install jupytext", vim.log.levels.WARN)
			vim.notify("Or run :PyworksSetup to set up this project", vim.log.levels.INFO)
			-- Show raw JSON as fallback
			local file = io.open(filepath, "r")
			if file then
				local content = file:read("*all")
				file:close()
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
				vim.api.nvim_buf_set_option(bufnr, "filetype", "json")
				vim.api.nvim_buf_set_option(bufnr, "modified", false)
			end
			return
		end
		
		-- Convert notebook to percent format
		local env_prefix = "PYTHONWARNINGS=ignore "
		local result = vim.fn.system(env_prefix .. string.format("jupytext --to auto:percent '%s' --output - 2>/dev/null", filepath))
		
		-- If auto-detection fails, try with Python format as fallback
		if vim.v.shell_error ~= 0 or not result or result == "" then
			result = vim.fn.system(env_prefix .. string.format("jupytext --to py:percent '%s' --output - 2>/dev/null", filepath))
		end
		
		if vim.v.shell_error == 0 and result and result ~= "" then
			-- Successfully converted
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result, "\n"))
			
			-- Detect filetype from content
			local filetype = "python"
			local lines = vim.split(result, "\n")
			for i = 1, math.min(20, #lines) do
				local line = lines[i] or ""
				if line:match("extension: %.jl") or line:match("language: julia") then
					filetype = "julia"
					break
				elseif line:match("extension: %.r") or line:match("extension: %.R") or line:match("language: r") or line:match("language: R") then
					filetype = "r"
					break
				end
			end
			
			vim.api.nvim_buf_set_option(bufnr, "filetype", filetype)
			vim.api.nvim_buf_set_option(bufnr, "modified", false)
			
			-- Show pyworks-specific messages
			local notebook_type = filetype:gsub("^%l", string.upper)
			vim.notify("📓 " .. notebook_type .. " notebook opened", vim.log.levels.INFO)
			
			-- Analyze imports after a delay to let the buffer settle
			vim.defer_fn(function()
				local detector = require("pyworks.package-detector")
				detector.analyze_buffer()
			end, 1500)
			
			-- Check if virtual environment exists
			local venv_exists = vim.fn.isdirectory(vim.fn.getcwd() .. "/.venv") == 1
			if not venv_exists then
				-- Guide through pyworks setup workflow
				vim.notify("💡 Run :PyworksSetup and choose 'Data Science / Notebooks'", vim.log.levels.INFO)
				vim.notify("   This will set up Python environment with Jupyter support", vim.log.levels.INFO)
			else
				-- Check if essential packages are installed
				local has_jupyter = vim.fn.system("cd " .. vim.fn.getcwd() .. " && .venv/bin/python -c 'import jupyter_client' 2>/dev/null")
				if vim.v.shell_error ~= 0 then
					vim.notify("💡 Run :PyworksSetup to install Jupyter dependencies", vim.log.levels.INFO)
				else
					-- Smart kernel detection and auto-initialization
					vim.defer_fn(function()
						-- Check if MoltenInit command exists
						if vim.fn.exists(":MoltenInit") ~= 2 then
							vim.notify("⚠️ Molten not loaded. Restart Neovim after :PyworksSetup", vim.log.levels.WARN)
							return
						end
						
						-- Get list of available kernels
						local kernels_list = vim.fn.system("jupyter kernelspec list --json 2>/dev/null")
						if vim.v.shell_error == 0 and kernels_list then
							local ok, kernels_data = pcall(vim.json.decode, kernels_list)
							if ok and kernels_data and kernels_data.kernelspecs then
								local available_kernels = {}
								for kernel_name, _ in pairs(kernels_data.kernelspecs) do
									table.insert(available_kernels, kernel_name)
								end
								
								-- Find matching kernel for the detected file type
								local matching_kernel = nil
								local kernel_to_find = ""
								local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
								
								if filetype == "python" then
									kernel_to_find = "python3"
									-- First try project-specific kernel
									for _, k in ipairs(available_kernels) do
										if k == project_name or k:match(project_name) then
											matching_kernel = k
											break
										end
									end
									-- Fall back to generic python kernel
									if not matching_kernel then
										for _, k in ipairs(available_kernels) do
											if k == "python3" or k:match("^python") then
												matching_kernel = k
												break
											end
										end
									end
								elseif filetype == "julia" then
									kernel_to_find = "julia"
									for _, k in ipairs(available_kernels) do
										if k:match("^julia") then
											matching_kernel = k
											break
										end
									end
								elseif filetype == "r" then
									kernel_to_find = "ir"
									for _, k in ipairs(available_kernels) do
										if k == "ir" or k:match("^ir$") then
											matching_kernel = k
											break
										end
									end
								end
								
								if matching_kernel then
									-- Auto-initialize the matching kernel
									vim.notify("✓ Found " .. matching_kernel .. " kernel, auto-initializing...", vim.log.levels.INFO)
									vim.schedule(function()
										local ok = pcall(vim.cmd, "MoltenInit " .. matching_kernel)
										if ok then
											vim.b[bufnr].molten_kernel_initialized = true
											
											-- Auto-fix output display after kernel init
											vim.defer_fn(function()
												if vim.fn.exists("*MoltenUpdateOption") == 1 then
													vim.cmd("silent! call MoltenUpdateOption('virt_text_output', v:false)")
													vim.cmd("silent! call MoltenUpdateOption('output_virt_lines', v:false)")
													vim.cmd("silent! call MoltenUpdateOption('virt_lines_off_by_1', v:false)")
												end
											end, 200)
											
											vim.notify("✓ Kernel ready! Use <leader>jl to run lines, <leader>jv for selections", vim.log.levels.INFO)
										else
											vim.notify("Failed to initialize kernel. Press <leader>ji to try manually", vim.log.levels.WARN)
										end
									end)
								elseif #available_kernels > 0 then
									-- No matching kernel but others available - show selection
									vim.notify("⚠️ No " .. kernel_to_find .. " kernel found", vim.log.levels.WARN)
									vim.notify("💡 Press <leader>ji to select from available kernels", vim.log.levels.INFO)
								else
									-- No kernels at all
									vim.notify("⚠️ No Jupyter kernels found!", vim.log.levels.WARN)
									vim.notify("💡 Install kernels: python -m ipykernel install --user", vim.log.levels.INFO)
								end
							end
						else
							-- Jupyter command failed - guide to setup
							vim.notify("💡 Press <leader>ji to initialize kernel", vim.log.levels.INFO)
						end
					end, 1000) -- Delay to let buffer settle
				end
			end
			
			-- Set up write command to save back to notebook
			vim.api.nvim_create_autocmd({"BufWriteCmd", "FileWriteCmd"}, {
				buffer = bufnr,
				callback = function()
					-- Get current buffer content
					local lines_to_save = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
					local temp_file = vim.fn.tempname() .. ".py"
					
					-- Write to temp file
					local f = io.open(temp_file, "w")
					if f then
						f:write(table.concat(lines_to_save, "\n"))
						f:close()
						
						-- Convert back to notebook
						vim.fn.system(string.format("PYTHONWARNINGS=ignore jupytext --to notebook '%s' --output '%s' 2>/dev/null", temp_file, filepath))
						if vim.v.shell_error == 0 then
							vim.api.nvim_buf_set_option(bufnr, "modified", false)
							vim.notify("Saved notebook: " .. vim.fn.fnamemodify(filepath, ":t"), vim.log.levels.INFO)
						else
							vim.notify("Failed to save notebook", vim.log.levels.ERROR)
						end
						
						-- Clean up temp file
						vim.fn.delete(temp_file)
					end
				end,
			})
		else
			-- Conversion failed - show raw JSON
			local file = io.open(filepath, "r")
			if file then
				local content = file:read("*all")
				file:close()
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
				vim.api.nvim_buf_set_option(bufnr, "filetype", "json")
				vim.api.nvim_buf_set_option(bufnr, "modified", false)
				vim.notify("Showing raw notebook (jupytext conversion failed)", vim.log.levels.WARN)
			end
		end
	end,
})