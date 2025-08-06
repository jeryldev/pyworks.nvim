-- Kernel management utilities for pyworks
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
	
	-- Check if ipykernel is installed
	local has_ipykernel = vim.fn.system(python_path .. " -c 'import ipykernel' 2>/dev/null")
	if vim.v.shell_error ~= 0 then
		return false, "ipykernel not installed"
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

-- Get the best kernel for current project
function M.get_best_kernel()
	local success, kernel_name = M.ensure_project_kernel()
	if success then
		return kernel_name
	end
	
	-- Fall back to python3 kernel
	return "python3"
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

return M