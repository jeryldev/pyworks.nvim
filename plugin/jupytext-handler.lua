-- Handle .ipynb files with jupytext CLI
-- This runs when pyworks.nvim loads as a plugin

-- Our handler for notebooks
vim.api.nvim_create_autocmd("BufReadCmd", {
	pattern = "*.ipynb",
	group = vim.api.nvim_create_augroup("PyworksNotebooks", { clear = true }),
	callback = function(args)
		local filepath = args.file
		local bufnr = args.buf
		
		-- First, check if jupytext is available
		local jupytext_available = vim.fn.executable("jupytext") == 1
		if not jupytext_available then
			-- Try to find jupytext in current venv
			local cwd = vim.fn.getcwd()
			local venv_jupytext = cwd .. "/.venv/bin/jupytext"
			if vim.fn.executable(venv_jupytext) == 1 then
				jupytext_available = true
			end
		end
		
		local result = ""
		if jupytext_available then
			-- First try auto-detection (this might fail if metadata is incomplete)
			result = vim.fn.system(string.format("jupytext --to auto:percent '%s' --output - 2>&1", filepath))
			local auto_success = vim.v.shell_error == 0 and result and result ~= "" and not result:match("ValueError")
			
			-- If auto-detection fails, try with Python format as fallback
			if not auto_success then
				result = vim.fn.system(string.format("jupytext --to py:percent '%s' --output - 2>/dev/null", filepath))
			end
		end
		
		if jupytext_available and vim.v.shell_error == 0 and result and result ~= "" then
			-- Successfully converted
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result, "\n"))
			
			-- Detect filetype from the content - check multiple lines for metadata
			local lines = vim.split(result, "\n")
			local filetype = "python"
			for i = 1, math.min(20, #lines) do
				local line = lines[i] or ""
				if line:match("extension: %.jl") then
					filetype = "julia"
					-- Disable Python LSP for Julia notebooks
					vim.b[bufnr].pyright_disable = true
					break
				elseif line:match("extension: %.r") or line:match("extension: %.R") then
					filetype = "r"
					-- Disable Python LSP for R notebooks
					vim.b[bufnr].pyright_disable = true
					break
				elseif line:match("language: julia") then
					filetype = "julia"
					vim.b[bufnr].pyright_disable = true
					break
				elseif line:match("language: R") or line:match("language: r") then
					filetype = "r"
					vim.b[bufnr].pyright_disable = true
					break
				end
			end
			vim.api.nvim_buf_set_option(bufnr, "filetype", filetype)
			vim.api.nvim_buf_set_option(bufnr, "modified", false)
			
			-- Show notification about detected notebook type and try to auto-initialize matching kernel
			vim.defer_fn(function()
				local notebook_type = filetype:gsub("^%l", string.upper)
				vim.notify("📓 " .. notebook_type .. " notebook opened.", vim.log.levels.INFO)
				
				-- Get available kernels with proper error handling
				local available_kernels = {}
				local kernels_ok, kernels_result = pcall(function()
					return vim.fn.MoltenAvailableKernels()
				end)
				
				if kernels_ok and kernels_result then
					available_kernels = kernels_result
				else
					-- Molten not available - show message but don't block the workflow
					vim.notify("Kernel detection pending. If kernels are installed, try :MoltenInit", vim.log.levels.INFO)
					return
				end
				
				-- Find matching kernel for the detected file type
				local has_matching_kernel = false
				local kernel_name = ""
				
				for _, k in ipairs(available_kernels) do
					if (filetype == "julia" and k:match("julia")) then
						has_matching_kernel = true
						kernel_name = k
						break
					elseif (filetype == "r" and (k == "ir" or k:match("^ir$"))) then
						has_matching_kernel = true
						kernel_name = "ir"
						break
					elseif (filetype == "python" and k:match("python")) then
						has_matching_kernel = true
						kernel_name = k
						break
					end
				end
				
				-- Auto-initialize matching kernel if found, or show selection dialog
				if has_matching_kernel then
					vim.notify("✓ " .. kernel_name .. " kernel detected.", vim.log.levels.INFO)
					
					-- Auto-initialize the matching kernel in the background
					vim.defer_fn(function()
						local ok = pcall(vim.cmd, "MoltenInit " .. kernel_name)
						if ok then
							-- Mark buffer as having initialized kernel
							vim.b[bufnr].kernel_initialized = true
							vim.notify("✓ " .. kernel_name .. " kernel initialized.", vim.log.levels.INFO)
						else
							vim.notify("⚠ Failed to initialize " .. kernel_name .. " kernel.", vim.log.levels.WARN)
						end
					end, 500)  -- Auto-initialize in background
				elseif #available_kernels > 0 then
					-- No matching kernel but other kernels available - show selection dialog
					local expected_kernel = filetype == "r" and "ir" or (filetype == "julia" and "julia" or "python3")
					vim.notify("⚠ " .. expected_kernel .. " kernel not found. Other kernels available.", vim.log.levels.WARN)
					
					-- Use the existing molten init function to show selection dialog
					vim.defer_fn(function()
						local molten = require("pyworks.molten")
						molten.init_kernel(false)
					end, 800)  -- Slight delay to let user read the warning
				else
					-- No kernels available at all
					local expected_kernel = filetype == "r" and "ir" or (filetype == "julia" and "julia" or "python3")
					vim.notify("⚠ " .. expected_kernel .. " kernel not found.", vim.log.levels.WARN)
				end
			end, 500)  -- Delay to ensure Molten is ready
			
			-- Set up write command to save back to notebook
			vim.api.nvim_create_autocmd({"BufWriteCmd", "FileWriteCmd"}, {
				buffer = bufnr,
				callback = function()
					-- Get current buffer content
					local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
					local temp_file = vim.fn.tempname() .. ".py"
					
					-- Write to temp file
					local f = io.open(temp_file, "w")
					if f then
						f:write(table.concat(lines, "\n"))
						f:close()
						
						-- Convert back to notebook
						vim.fn.system(string.format("jupytext --to notebook '%s' --output '%s'", temp_file, filepath))
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
			return
		end
		
		-- If jupytext CLI failed, try to fix metadata and retry
		local file = io.open(filepath, "r")
		if file then
			local content = file:read("*all")
			file:close()
			
			local ok, notebook = pcall(vim.json.decode, content)
			if ok and notebook then
				local needs_update = false
				
				-- Ensure metadata exists
				if not notebook.metadata then
					notebook.metadata = {}
					needs_update = true
				end
				
				-- Only add Python metadata if no language is specified at all
				if not notebook.metadata.language_info or not notebook.metadata.language_info.name then
					-- Check if kernelspec exists and has a language
					local language = nil
					if notebook.metadata.kernelspec and notebook.metadata.kernelspec.language then
						language = notebook.metadata.kernelspec.language
					end
					
					-- Default to Python only if no language detected
					if not language then
						notebook.metadata.language_info = {
							codemirror_mode = { name = "ipython", version = 3 },
							file_extension = ".py",
							mimetype = "text/x-python",
							name = "python",
							nbconvert_exporter = "python",
							pygments_lexer = "ipython3",
							version = "3.11.0",
						}
						needs_update = true
					end
				end
				
				-- Only add Python kernelspec if no kernelspec exists at all
				if not notebook.metadata.kernelspec then
					-- Only default to Python if no other language info exists
					if not notebook.metadata.language_info or notebook.metadata.language_info.name == "python" then
						notebook.metadata.kernelspec = {
							display_name = "Python 3",
							language = "python",
							name = "python3",
						}
						needs_update = true
					end
				end
				
				-- Write back if updated and retry
				if needs_update then
					local fixed_json = vim.json.encode(notebook)
					local write_file = io.open(filepath, "w")
					if write_file then
						write_file:write(fixed_json)
						write_file:close()
						
						-- Retry conversion with auto detection (if jupytext is available)
						if jupytext_available then
							result = vim.fn.system(string.format("jupytext --to auto:percent '%s' --output - 2>&1", filepath))
							local auto_success = vim.v.shell_error == 0 and result and result ~= "" and not result:match("ValueError")
							
							-- If auto-detection fails, try with Python format as fallback
							if not auto_success then
								result = vim.fn.system(string.format("jupytext --to py:percent '%s' --output - 2>/dev/null", filepath))
							end
						end
						if jupytext_available and vim.v.shell_error == 0 and result and result ~= "" then
							vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result, "\n"))
							-- Detect filetype from the content - check multiple lines for metadata
							local lines = vim.split(result, "\n")
							local filetype = "python"
							for i = 1, math.min(20, #lines) do
								local line = lines[i] or ""
								if line:match("extension: %.jl") then
									filetype = "julia"
									vim.b[bufnr].pyright_disable = true
									break
								elseif line:match("extension: %.r") or line:match("extension: %.R") then
									filetype = "r"
									vim.b[bufnr].pyright_disable = true
									break
								elseif line:match("language: julia") then
									filetype = "julia"
									vim.b[bufnr].pyright_disable = true
									break
								elseif line:match("language: R") or line:match("language: r") then
									filetype = "r"
									vim.b[bufnr].pyright_disable = true
									break
								end
							end
							vim.api.nvim_buf_set_option(bufnr, "filetype", filetype)
							vim.api.nvim_buf_set_option(bufnr, "modified", false)
							
							-- Show notification about detected notebook type and try to auto-initialize matching kernel
							vim.defer_fn(function()
								local notebook_type = filetype:gsub("^%l", string.upper)
								vim.notify("📓 " .. notebook_type .. " notebook opened.", vim.log.levels.INFO)
								
								-- Get available kernels with proper error handling
								local available_kernels = {}
								local kernels_ok, kernels_result = pcall(function()
									return vim.fn.MoltenAvailableKernels()
								end)
								
								if kernels_ok and kernels_result then
									available_kernels = kernels_result
								else
									-- Molten not available - show message but don't block the workflow
									vim.notify("Kernel detection pending. If kernels are installed, try :MoltenInit", vim.log.levels.INFO)
									return
								end
								
								-- Find matching kernel for the detected file type
								local has_matching_kernel = false
								local kernel_name = ""
								
								for _, k in ipairs(available_kernels) do
									if (filetype == "julia" and k:match("julia")) then
										has_matching_kernel = true
										kernel_name = k
										break
									elseif (filetype == "r" and (k == "ir" or k:match("^ir$"))) then
										has_matching_kernel = true
										kernel_name = "ir"
										break
									elseif (filetype == "python" and k:match("python")) then
										has_matching_kernel = true
										kernel_name = k
										break
									end
								end
								
								-- Auto-initialize matching kernel if found, or show selection dialog
								if has_matching_kernel then
									vim.notify("✓ " .. kernel_name .. " kernel detected.", vim.log.levels.INFO)
									
									-- Auto-initialize the matching kernel in the background
									vim.defer_fn(function()
										local ok = pcall(vim.cmd, "MoltenInit " .. kernel_name)
										if ok then
											-- Mark buffer as having initialized kernel
											vim.b[bufnr].kernel_initialized = true
											vim.notify("✓ " .. kernel_name .. " kernel initialized.", vim.log.levels.INFO)
										else
											vim.notify("⚠ Failed to initialize " .. kernel_name .. " kernel.", vim.log.levels.WARN)
										end
									end, 500)  -- Auto-initialize in background
								elseif #available_kernels > 0 then
									-- No matching kernel but other kernels available - show selection dialog
									local expected_kernel = filetype == "r" and "ir" or (filetype == "julia" and "julia" or "python3")
									vim.notify("⚠ " .. expected_kernel .. " kernel not found. Other kernels available.", vim.log.levels.WARN)
									
									-- Use the existing molten init function to show selection dialog
									vim.defer_fn(function()
										local molten = require("pyworks.molten")
										molten.init_kernel(false)
									end, 800)  -- Slight delay to let user read the warning
								else
									-- No kernels available at all
									local expected_kernel = filetype == "r" and "ir" or (filetype == "julia" and "julia" or "python3")
									vim.notify("⚠ " .. expected_kernel .. " kernel not found.", vim.log.levels.WARN)
								end
							end, 500)  -- Delay to ensure Molten is ready
							
							return
						end
					end
				end
				
				-- Last resort: show JSON
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
				vim.api.nvim_buf_set_option(bufnr, "filetype", "json")
				vim.api.nvim_buf_set_option(bufnr, "modified", false)
				if not jupytext_available then
					vim.notify("Jupytext not found. Install with: pip install jupytext", vim.log.levels.WARN)
					vim.notify("Or run :PyworksSetup to set up this project", vim.log.levels.INFO)
				else
					vim.notify("Showing raw notebook (jupytext conversion failed)", vim.log.levels.WARN)
				end
			end
		end
	end,
})

-- Remove any conflicting jupytext.nvim autocmds
vim.defer_fn(function()
	local autocmds = vim.api.nvim_get_autocmds({
		event = "BufReadCmd",
		pattern = "*.ipynb",
	})
	for _, autocmd in ipairs(autocmds) do
		if autocmd.group_name == "jupytext" then
			pcall(vim.api.nvim_del_autocmd, autocmd.id)
		end
	end
end, 100)