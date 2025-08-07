-- Kernel management utilities for pyworks
-- Handles creating and selecting project-specific Jupyter kernels
local M = {}
local utils = require("pyworks.utils")

-- Ensure project-specific kernel exists
function M.ensure_project_kernel()
	local cwd = vim.fn.getcwd()
	local venv_path = cwd .. "/.venv"
	local python_path = venv_path .. "/bin/python3"
	
	-- Check if venv exists
	if vim.fn.isdirectory(venv_path) == 0 then
		return false, "No virtual environment found"
	end
	
	-- Check if python exists
	if vim.fn.executable(python_path) == 0 then
		python_path = venv_path .. "/bin/python"
		if vim.fn.executable(python_path) == 0 then
			return false, "Python not found in virtual environment"
		end
	end
	
	-- Check and install required packages
	local required_packages = { "ipykernel", "jupyter_client", "pynvim" }
	local missing_packages = {}
	
	for _, pkg in ipairs(required_packages) do
		local check_cmd = python_path .. " -c 'import " .. pkg .. "' 2>/dev/null"
		vim.fn.system(check_cmd)
		if vim.v.shell_error ~= 0 then
			table.insert(missing_packages, pkg)
		end
	end
	
	if #missing_packages > 0 then
		utils.notify("Installing required packages: " .. table.concat(missing_packages, ", "), vim.log.levels.INFO)
		for _, pkg in ipairs(missing_packages) do
			local install_cmd = python_path .. " -m pip install " .. pkg .. " 2>&1"
			vim.fn.system(install_cmd)
		end
	end
	
	-- Get project name for kernel
	local project_name = vim.fn.fnamemodify(cwd, ":t")
	
	-- Check if kernel already exists
	local kernels_list = vim.fn.system("jupyter kernelspec list --json 2>/dev/null")
	if vim.v.shell_error == 0 and kernels_list then
		local ok, kernels_data = pcall(vim.json.decode, kernels_list)
		if ok and kernels_data and kernels_data.kernelspecs then
			if kernels_data.kernelspecs[project_name] then
				-- Kernel exists, verify it points to the right Python
				local kernel_path = kernels_data.kernelspecs[project_name].resource_dir
				local kernel_json_path = kernel_path .. "/kernel.json"
				local kernel_json = vim.fn.readfile(kernel_json_path)
				if kernel_json then
					local kernel_str = table.concat(kernel_json, "\n")
					if kernel_str:match(vim.pesc(python_path)) then
						return true, project_name
					else
						-- Kernel exists but points to wrong Python, recreate it
						vim.fn.system("jupyter kernelspec remove -f " .. project_name .. " 2>/dev/null")
					end
				end
			end
		end
	end
	
	-- Create the kernel
	local kernel_cmd = string.format(
		"%s -m ipykernel install --user --name %s --display-name 'Python (%s)' 2>/dev/null",
		python_path, project_name, project_name
	)
	vim.fn.system(kernel_cmd)
	
	if vim.v.shell_error == 0 then
		return true, project_name
	else
		return false, "Failed to create kernel"
	end
end

-- Verify a kernel has required packages and points to the right Python
function M.verify_kernel(kernel_name, expected_project_path)
	local kernels_list = vim.fn.system("jupyter kernelspec list --json 2>/dev/null")
	if vim.v.shell_error ~= 0 then
		return false, "Cannot list kernels"
	end
	
	local ok, kernels_data = pcall(vim.json.decode, kernels_list)
	if not ok or not kernels_data or not kernels_data.kernelspecs then
		return false, "Invalid kernel data"
	end
	
	local kernel_spec = kernels_data.kernelspecs[kernel_name]
	if not kernel_spec then
		return false, "Kernel not found"
	end
	
	-- Read kernel.json to get Python path
	local kernel_json_path = kernel_spec.resource_dir .. "/kernel.json"
	local kernel_json = vim.fn.readfile(kernel_json_path)
	if not kernel_json then
		return false, "Cannot read kernel spec"
	end
	
	local kernel_str = table.concat(kernel_json, "\n")
	local kernel_data = vim.json.decode(kernel_str)
	if not kernel_data or not kernel_data.argv or #kernel_data.argv == 0 then
		return false, "Invalid kernel spec"
	end
	
	local python_exe = kernel_data.argv[1]
	
	-- If expected project path is given, check if kernel uses that project's Python
	if expected_project_path then
		if not python_exe:match(vim.pesc(expected_project_path)) then
			return false, "Kernel uses different project's Python"
		end
	end
	
	-- Check required packages
	local check_cmd = python_exe .. " -c 'import ipykernel, jupyter_client, pynvim' 2>&1"
	local result = vim.fn.system(check_cmd)
	if vim.v.shell_error ~= 0 then
		-- Try to identify what's missing
		local missing = {}
		for _, pkg in ipairs({"ipykernel", "jupyter_client", "pynvim"}) do
			local single_check = python_exe .. " -c 'import " .. pkg .. "' 2>&1"
			vim.fn.system(single_check)
			if vim.v.shell_error ~= 0 then
				table.insert(missing, pkg)
			end
		end
		if #missing > 0 then
			return false, "Missing: " .. table.concat(missing, ", "), python_exe
		end
		return false, "Unknown error"
	end
	
	return true, "OK", python_exe
end

-- Get the best kernel for current project
function M.get_best_kernel()
	local cwd = vim.fn.getcwd()
	local project_name = vim.fn.fnamemodify(cwd, ":t")
	
	-- First, check if a project-specific kernel exists and is valid
	local verified, msg, python_exe = M.verify_kernel(project_name, cwd)
	if verified then
		return project_name
	elseif msg:match("Missing:") and python_exe then
		-- Kernel exists but missing packages - try to fix automatically
		utils.notify("Kernel '" .. project_name .. "' " .. msg, vim.log.levels.WARN)
		utils.notify("Auto-fixing kernel...", vim.log.levels.INFO)
		
		-- Install missing packages
		local missing = msg:match("Missing: (.+)")
		if missing then
			for pkg in missing:gmatch("[^,]+") do
				pkg = pkg:match("^%s*(.-)%s*$") -- trim whitespace
				local install_cmd = python_exe .. " -m pip install " .. pkg .. " 2>&1"
				vim.fn.system(install_cmd)
			end
		end
		
		-- Don't use this kernel yet, fall through to alternatives
		utils.notify("Kernel will be ready after package installation", vim.log.levels.INFO)
	elseif msg == "Kernel uses different project's Python" then
		-- This kernel is for a different project, don't use it
		utils.notify("Skipping '" .. project_name .. "' kernel (different project)", vim.log.levels.DEBUG)
	end
	
	-- Try to create a project kernel if we have a venv
	local success, kernel_name = M.ensure_project_kernel()
	if success then
		return kernel_name
	end
	
	-- Fall back to python3 kernel if it's valid
	local python3_ok = M.verify_kernel("python3")
	if python3_ok then
		return "python3"
	end
	
	-- Last resort - any Python kernel
	local kernels = M.list_kernels()
	for _, kernel in ipairs(kernels) do
		if kernel.name:match("python") then
			local ok = M.verify_kernel(kernel.name)
			if ok then
				return kernel.name
			end
		end
	end
	
	return nil
end

-- List all available kernels
function M.list_kernels()
	local kernels = {}
	local kernels_list = vim.fn.system("jupyter kernelspec list --json 2>/dev/null")
	
	if vim.v.shell_error == 0 and kernels_list then
		local ok, kernels_data = pcall(vim.json.decode, kernels_list)
		if ok and kernels_data and kernels_data.kernelspecs then
			for kernel_name, kernel_info in pairs(kernels_data.kernelspecs) do
				table.insert(kernels, {
					name = kernel_name,
					display = kernel_info.spec and kernel_info.spec.display_name or kernel_name,
					path = kernel_info.resource_dir
				})
			end
		end
	end
	
	return kernels
end

-- Remove project kernel (for cleanup)
function M.remove_project_kernel()
	local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
	vim.fn.system("jupyter kernelspec remove -f " .. project_name .. " 2>/dev/null")
	if vim.v.shell_error == 0 then
		utils.notify("Removed kernel: " .. project_name, vim.log.levels.INFO)
		return true
	end
	return false
end

-- Fix a kernel by installing missing packages
function M.fix_kernel(kernel_name)
	kernel_name = kernel_name or vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
	
	local verified, msg, python_exe = M.verify_kernel(kernel_name)
	if verified then
		utils.notify("Kernel '" .. kernel_name .. "' is already working", vim.log.levels.INFO)
		return true
	end
	
	if not python_exe then
		utils.notify("Cannot find Python for kernel '" .. kernel_name .. "'", vim.log.levels.ERROR)
		return false
	end
	
	if msg:match("Missing:") then
		local missing = msg:match("Missing: (.+)")
		utils.notify("Installing missing packages for '" .. kernel_name .. "': " .. missing, vim.log.levels.INFO)
		
		for pkg in missing:gmatch("[^,]+") do
			pkg = pkg:match("^%s*(.-)%s*$") -- trim whitespace
			local install_cmd = python_exe .. " -m pip install " .. pkg .. " 2>&1"
			utils.notify("Installing " .. pkg .. "...", vim.log.levels.INFO)
			vim.fn.system(install_cmd)
		end
		
		-- Verify again
		local ok = M.verify_kernel(kernel_name)
		if ok then
			utils.notify("✓ Kernel '" .. kernel_name .. "' fixed!", vim.log.levels.INFO)
			return true
		else
			utils.notify("Failed to fix kernel", vim.log.levels.ERROR)
			return false
		end
	else
		utils.notify("Cannot fix kernel: " .. msg, vim.log.levels.ERROR)
		return false
	end
end

return M