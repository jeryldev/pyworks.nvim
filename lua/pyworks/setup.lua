-- pyworks.nvim - Setup module
-- Handles project setup and package installation

local M = {}

-- Package display name to import name mapping
M.package_map = {
	["scikit-learn"] = "sklearn",
	["opencv-python"] = "cv2",
	["pillow"] = "PIL",
	["beautifulsoup4"] = "bs4",
	["python-dotenv"] = "dotenv",
	["redis-py"] = "redis",
	["scikit-image"] = "skimage",
}

-- Project templates
M.project_templates = {
	{
		name = "Data Science / Notebooks",
		essential = { "pynvim", "jupyter_client", "ipykernel", "jupytext" },
		optional = {
			"numpy",
			"pandas",
			"matplotlib",
			"seaborn",
			"scikit-learn",
			"scipy",
			"statsmodels",
			"plotly",
			"notebook",
			"tensorflow",
			"torch",
			"torchvision",
		},
		create_nvim_lua = true,
	},
	{
		name = "Web Development (FastAPI/Flask/Django)",
		essential = { "pynvim" },
		optional = {
			"fastapi",
			"uvicorn[standard]",
			"flask",
			"django",
			"sqlalchemy",
			"alembic",
			"pydantic",
			"python-dotenv",
			"requests",
			"httpx",
			"pytest",
			"black",
			"ruff",
		},
		create_nvim_lua = false,
	},
	{
		name = "General Python Development",
		essential = { "pynvim" },
		optional = {
			"pytest",
			"black",
			"ruff",
			"mypy",
			"ipython",
			"python-dotenv",
			"rich",
			"typer",
			"click",
		},
		create_nvim_lua = false,
	},
	{
		name = "Automation / Scripting",
		essential = { "pynvim" },
		optional = {
			"requests",
			"beautifulsoup4",
			"selenium",
			"pandas",
			"schedule",
			"python-dotenv",
			"rich",
			"typer",
		},
		create_nvim_lua = false,
	},
	{
		name = "Custom (choose your own packages)",
		essential = { "pynvim" },
		optional = {},
		create_nvim_lua = nil, -- Will ask
	},
}

-- Check if setup is needed
function M.is_setup_needed()
	local venv_path = vim.fn.getcwd() .. "/.venv"
	local python_path = venv_path .. "/bin/python3"

	-- Check if venv exists
	if vim.fn.isdirectory(venv_path) == 0 then
		return true, "No virtual environment found"
	end

	-- Check if Python host is set correctly
	if vim.g.python3_host_prog ~= python_path then
		return true, "Python host not configured for this project"
	end

	-- Check essential packages
	local essential_packages = { "pynvim" }
	for _, pkg in ipairs(essential_packages) do
		local check_cmd = string.format("%s -c 'import %s' 2>/dev/null", python_path, pkg)
		if vim.fn.system(check_cmd) ~= "" then
			return true, "Missing essential package: " .. pkg
		end
	end

	return false, "Setup complete"
end

-- Main setup function
function M.setup_project()
	local venv_path = vim.fn.getcwd() .. "/.venv"
	local python_path = venv_path .. "/bin/python3"

	-- Check if venv exists, create if it doesn't
	if vim.fn.isdirectory(venv_path) == 0 then
		local has_uv = vim.fn.executable("uv") == 1
		local msg = has_uv and "No .venv found. Create virtual environment with uv?"
			or "No .venv found. Create virtual environment with python?"
		local choice = vim.fn.confirm(msg, "&Yes\n&Cancel", 1)

		if choice ~= 1 then
			return
		end

		vim.notify("Creating virtual environment" .. (has_uv and " with uv..." or "..."))
		local create_cmd = has_uv and "uv venv" or "python3 -m venv .venv"

		local result = vim.fn.system("cd " .. vim.fn.getcwd() .. " && " .. create_cmd)
		if vim.v.shell_error ~= 0 then
			vim.notify("Failed to create virtual environment: " .. result, vim.log.levels.ERROR)
			return
		end

		vim.notify("Virtual environment created successfully!", vim.log.levels.INFO)
		vim.notify("Please activate the virtual environment and re-run :PyworksSetup", vim.log.levels.WARN)
		vim.notify("Run: source .venv/bin/activate", vim.log.levels.INFO)
		return
	end

	-- Check if venv is activated
	local current_python = vim.fn.exepath("python3")
	if not current_python:match(venv_path) then
		vim.notify("Virtual environment not activated. Please run: source .venv/bin/activate", vim.log.levels.WARN)
		vim.notify(
			"Note: This works the same whether you created the venv with uv or python -m venv",
			vim.log.levels.INFO
		)
	end

	-- Ask what type of project this is
	local project_types = { "Select project type:" }
	for i, template in ipairs(M.project_templates) do
		table.insert(project_types, i .. ". " .. template.name)
	end

	local choice
	if vim.g._pyworks_project_type then
		choice = vim.g._pyworks_project_type
	else
		choice = vim.fn.inputlist(project_types)
	end

	if choice == 0 then
		vim.notify("Setup cancelled", vim.log.levels.INFO)
		return
	end

	local template = M.project_templates[choice]
	vim.notify("Setting up " .. template.name .. " environment with Python: " .. python_path)

	-- Set Python host
	vim.g.python3_host_prog = python_path

	-- Install packages
	local has_uv = vim.fn.executable("uv") == 1

	-- Check and install essential packages
	local missing_essential = M.check_missing_packages(python_path, template.essential)
	if #missing_essential > 0 then
		M.install_packages(missing_essential, python_path, has_uv, "essential")
	else
		vim.notify("Essential packages already installed", vim.log.levels.INFO)
	end

	-- Check and install optional packages
	if #template.optional > 0 then
		local missing_optional = M.check_missing_packages(python_path, template.optional)
		if #missing_optional > 0 then
			vim.notify(#missing_optional .. " project packages missing: " .. table.concat(missing_optional, ", "))
			local pkg_choice =
				vim.fn.confirm("Install project packages now?", "&Yes\n&No (install later)\n&Show list", 1)

			if pkg_choice == 1 then
				M.install_packages_async(missing_optional, vim.fn.getcwd(), python_path, has_uv)
			elseif pkg_choice == 3 then
				vim.notify("Missing: " .. table.concat(missing_optional, ", "), vim.log.levels.INFO)
			end
		end
	elseif choice == 5 then -- Custom
		local custom = vim.fn.input("Enter packages (space-separated): ")
		if custom ~= "" then
			local packages = vim.split(custom, " ")
			M.install_packages_async(packages, vim.fn.getcwd(), python_path, has_uv)
		end
	end

	-- Update remote plugins
	vim.notify("Updating remote plugins...")
	local update_cmd = string.format("NVIM_PYTHON3_HOST_PROG=%s nvim --headless +UpdateRemotePlugins +qa", python_path)
	vim.fn.system(update_cmd)

	-- Write .nvim.lua if needed
	local create_nvim_lua = template.create_nvim_lua
	if create_nvim_lua == nil then -- Custom project
		create_nvim_lua = vim.fn.confirm("Create .nvim.lua for Python host?", "&Yes\n&No", 2) == 1
	end

	if create_nvim_lua then
		local nvim_config = string.format("vim.g.python3_host_prog = '%s'", python_path)
		local config_file = io.open(".nvim.lua", "w")
		if config_file then
			config_file:write(nvim_config)
			config_file:close()
			vim.notify("Created .nvim.lua with Python host configuration", vim.log.levels.INFO)
		end
	end

	vim.notify("Pyworks setup complete!", vim.log.levels.INFO)
	vim.notify("Please restart Neovim for changes to take effect", vim.log.levels.WARN)
end

-- Check for missing packages
function M.check_missing_packages(python_path, packages)
	local missing = {}
	for _, pkg in ipairs(packages) do
		local import_name = M.package_map[pkg] or pkg:gsub("-", "_")
		local check_cmd = string.format("%s -c 'import %s' 2>&1", python_path, import_name)
		local result = vim.fn.system(check_cmd)
		if vim.v.shell_error ~= 0 then
			table.insert(missing, pkg)
		end
	end
	return missing
end

-- Install packages (synchronous)
function M.install_packages(packages, python_path, has_uv, package_type)
	vim.notify("Installing " .. package_type .. " packages: " .. table.concat(packages, ", "))
	local install_cmd
	if has_uv then
		install_cmd = string.format("cd %s && uv pip install %s", vim.fn.getcwd(), table.concat(packages, " "))
	else
		install_cmd = string.format("%s -m pip install %s", python_path, table.concat(packages, " "))
	end

	local result = vim.fn.system(install_cmd)
	if vim.v.shell_error ~= 0 then
		vim.notify("Failed to install " .. package_type .. " packages: " .. result, vim.log.levels.ERROR)
		return false
	end
	return true
end

-- Install packages (asynchronous)
function M.install_packages_async(packages, cwd, python_path, has_uv)
	vim.notify("Installing packages in background...")
	vim.notify("You can continue working. Check :messages for progress.")

	-- Create install script
	local install_script = [[
#!/bin/bash
packages="%s"
echo "Installing: $packages"
if command -v uv &> /dev/null; then
  cd %s && uv pip install $packages
else
  %s -m pip install $packages
fi
]]

	local script_content = string.format(install_script, table.concat(packages, " "), cwd, python_path)

	-- Write temporary script
	local script_path = vim.fn.tempname() .. ".sh"
	local f = io.open(script_path, "w")
	f:write(script_content)
	f:close()

	-- Run in background
	local job_id = vim.fn.jobstart({ "bash", script_path }, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.schedule(function()
					vim.notify(
						"✓ Packages installed successfully!" .. (has_uv and " (using uv)" or ""),
						vim.log.levels.INFO
					)
				end)
			else
				vim.schedule(function()
					vim.notify(
						"⚠ Some packages failed to install. Run :PyworksCheck for details.",
						vim.log.levels.WARN
					)
				end)
			end
			os.remove(script_path)
		end,
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					vim.schedule(function()
						vim.notify("  " .. line, vim.log.levels.INFO)
					end)
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" and not line:match("WARNING") then
					vim.schedule(function()
						vim.notify("  ⚠ " .. line, vim.log.levels.WARN)
					end)
				end
			end
		end,
	})

	vim.notify("Installation job started (ID: " .. job_id .. ")", vim.log.levels.INFO)
end

return M
