-- pyworks.nvim - Setup module
-- Handles project setup and package installation

local M = {}

-- Helper function for better selection using vim.ui.select
local function better_select(prompt, items, callback)
	vim.ui.select(items, {
		prompt = prompt,
		format_item = function(item)
			return item
		end,
		kind = "select",
	}, function(item, idx)
		if callback then
			callback(idx, item)
		end
	end)
end

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
		essential = { "jupyter_client", "ipykernel" }, -- pynvim and jupytext are pre-installed
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
	},
	{
		name = "Web Development (FastAPI/Flask/Django)",
		essential = {}, -- pynvim is pre-installed
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
	},
	{
		name = "General Python Development",
		essential = {}, -- pynvim is pre-installed
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
	},
	{
		name = "Automation / Scripting",
		essential = {}, -- pynvim is pre-installed
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
	},
	{
		name = "Custom (choose your own packages)",
		essential = {}, -- pynvim is pre-installed
		optional = {},
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

	-- Check essential packages (these are pre-installed during venv creation)
	local essential_packages = { "pynvim", "jupytext" }
	for _, pkg in ipairs(essential_packages) do
		local check_cmd = string.format("%s -c 'import %s' 2>/dev/null", python_path, pkg)
		if vim.fn.system(check_cmd) ~= "" then
			return true, "Missing essential package: " .. pkg
		end
	end

	return false, "Setup complete"
end

-- Continue setup after venv creation
local function continue_after_venv_creation(venv_path, python_path)
	-- Ask what type of project this is
	local template_names = {}
	for _, template in ipairs(M.project_templates) do
		table.insert(template_names, template.name)
	end

	if vim.g._pyworks_project_type then
		local template = M.project_templates[vim.g._pyworks_project_type]
		M.continue_setup(template, python_path, venv_path)
	else
		-- Use better_select for proper focus
		better_select("Select project type:", template_names, function(choice, selected)
			if not choice then
				vim.notify("Setup cancelled", vim.log.levels.INFO)
				return
			end

			local template = M.project_templates[choice]
			M.continue_setup(template, python_path, venv_path)
		end)
	end
end

-- Main setup function
function M.setup_project()
	local venv_path = vim.fn.getcwd() .. "/.venv"
	local python_path = venv_path .. "/bin/python3"

	-- Check if venv exists, create if it doesn't
	if vim.fn.isdirectory(venv_path) == 0 then
		local has_uv = vim.fn.executable("uv") == 1
		local options = has_uv and {
			"Create virtual environment with uv",
			"Cancel setup",
		} or {
			"Create virtual environment with python",
			"Cancel setup",
		}

		better_select("Virtual environment setup:", options, function(choice, item)
			if not choice or choice ~= 1 then
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

			-- Add venv/bin to PATH immediately
			local venv_bin = venv_path .. "/bin"
			if not vim.env.PATH:match(venv_bin) then
				vim.env.PATH = venv_bin .. ":" .. vim.env.PATH
			end

			-- Set Python host immediately
			vim.g.python3_host_prog = python_path

			-- Install essential packages immediately (pynvim and jupytext)
			vim.notify("Installing essential packages (pynvim, jupytext)...")
			local essential_cmd
			if has_uv then
				-- Use system uv to install into the venv we just created
				-- uv pip install automatically detects and uses .venv in current directory
				essential_cmd = string.format("cd %s && uv pip install pynvim jupytext", vim.fn.getcwd())
			else
				essential_cmd = string.format("%s -m pip install pynvim jupytext", python_path)
			end

			local essential_result = vim.fn.system(essential_cmd)
			if vim.v.shell_error ~= 0 then
				vim.notify("Failed to install essential packages: " .. essential_result, vim.log.levels.ERROR)
				return
			end
			vim.notify("✓ pynvim and jupytext installed successfully!", vim.log.levels.INFO)

			-- Update remote plugins in the background
			vim.notify("Updating remote plugins...")
			local update_cmd =
				string.format("NVIM_PYTHON3_HOST_PROG=%s nvim --headless +UpdateRemotePlugins +qa", python_path)
			vim.fn.system(update_cmd)
			vim.notify("✓ Remote plugins updated!", vim.log.levels.INFO)

			-- Continue with the rest of the setup

			-- Now continue with project type selection
			continue_after_venv_creation(venv_path, python_path)
		end)
	else
		-- Venv already exists, continue with setup
		continue_after_venv_creation(venv_path, python_path)
	end
end

-- Continue setup after project type selection
function M.continue_setup(template, python_path, venv_path)
	vim.notify("Setting up " .. template.name .. " environment with Python: " .. python_path)

	-- Set Python host
	vim.g.python3_host_prog = python_path

	-- Install packages
	-- Check for uv in venv first, then system
	local venv_bin = venv_path .. "/bin"
	local has_uv = vim.fn.executable(venv_bin .. "/uv") == 1 or vim.fn.executable("uv") == 1

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
			better_select(
				"Project packages:",
				{ "Install now", "Skip installation", "Show missing packages" },
				function(pkg_choice)
					if pkg_choice == 1 then
						M.install_packages_async(missing_optional, vim.fn.getcwd(), python_path, has_uv)
					elseif pkg_choice == 3 then
						vim.notify("Missing: " .. table.concat(missing_optional, ", "), vim.log.levels.INFO)
					end

					-- Complete setup
					M.complete_setup(python_path)
				end
			)
			return -- Exit here, completion will happen in callback
		end
	end

	-- If we get here, no optional packages or none missing, complete setup
	M.complete_setup(python_path)
end

-- Complete the setup process
function M.complete_setup(python_path)
	-- Update remote plugins
	vim.notify("Updating remote plugins...")
	local update_cmd = string.format("NVIM_PYTHON3_HOST_PROG=%s nvim --headless +UpdateRemotePlugins +qa", python_path)
	vim.fn.system(update_cmd)

	-- Python host is automatically configured by pyworks autocmds

	vim.notify("Pyworks setup complete!", vim.log.levels.INFO)
	vim.notify("🎉 Everything is configured! Please restart Neovim once to activate Molten.", vim.log.levels.WARN)
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
						"⚠ Some packages failed to install. Run :PyworksCheckEnvironment for details.",
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
			-- Collect lines that are actually errors
			local has_error = false
			local error_lines = {}

			for _, line in ipairs(data) do
				if line ~= "" then
					-- Skip known non-error output from pip/uv
					if
						line:match("WARNING")
						or line:match("Collecting")
						or line:match("Using cached")
						or line:match("Installing collected packages")
						or line:match("Successfully installed")
						or line:match("Resolved %d+ packages")
						or line:match("Prepared %d+ packages")
						or line:match("Installed %d+ packages")
						or line:match("Audited %d+ packages")
						or line:match("^%s*%+%s*") -- Package install progress
						or line:match("^%s*[%w%-%.]+==[%d%.]+") -- Package with version (e.g., torch==2.7.1)
						or line:match("^%s*[%w%-%.]+%s*$") -- Package name only
						or line:match("^%s*⚠%s*[%w%-%.]+") -- Warning symbol with package
					then -- Package names
						-- This is normal output, not an error
					else
						-- This might be an actual error
						table.insert(error_lines, line)
						has_error = true
					end
				end
			end

			-- Only show actual errors
			if has_error then
				for _, line in ipairs(error_lines) do
					vim.schedule(function()
						vim.notify("  ⚠ " .. line, vim.log.levels.WARN)
					end)
				end
			end
		end,
	})
end

return M
