-- pyworks.nvim - Setup module
-- Handles project setup and package installation

local M = {}
local utils = require("pyworks.utils")

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
	local cwd, venv_path = utils.get_project_paths()
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
		utils.better_select("Select project type:", template_names, function(selected)
			if not selected then
				vim.notify("Setup cancelled", vim.log.levels.INFO)
				return
			end

			-- Find the template by name
			local template
			for idx, t in ipairs(M.project_templates) do
				if t.name == selected then
					template = t
					break
				end
			end

			if template then
				M.continue_setup(template, python_path, venv_path)
			else
				vim.notify("Invalid project type selected", vim.log.levels.ERROR)
			end
		end)
	end
end

-- Main setup function
function M.setup_project()
	local cwd, venv_path = utils.get_project_paths()
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

		utils.better_select("Virtual environment setup:", options, function(item)
			if not item or item ~= options[1] then
				return
			end

			-- Capture cwd in local scope for async callbacks
			local current_cwd = cwd

			vim.notify("Creating virtual environment" .. (has_uv and " with uv..." or "..."))
			local create_cmd = has_uv and "uv venv" or "python3 -m venv .venv"

			-- Start async venv creation
			local progress_id = utils.progress_start("Creating virtual environment")

			utils.async_system_call(create_cmd, function(success, stdout, stderr, exit_code)
				if not success then
					utils.progress_end(progress_id, false, stderr)
					return
				end

				utils.progress_end(progress_id, true)

				-- Add venv/bin to PATH immediately
				local venv_bin = venv_path .. "/bin"
				if not vim.env.PATH:match(venv_bin) then
					vim.env.PATH = venv_bin .. ":" .. vim.env.PATH
				end

				-- Set Python host immediately
				vim.g.python3_host_prog = python_path

				-- Install essential packages asynchronously
				utils.notify("Installing essential packages (pynvim, jupytext)...", vim.log.levels.INFO)
				local essential_cmd
				if has_uv then
					essential_cmd = "uv pip install pynvim jupytext"
				else
					essential_cmd = python_path .. " -m pip install pynvim jupytext"
				end

				local essential_progress = utils.progress_start("Installing essential packages")
				utils.async_system_call(essential_cmd, function(pkg_success, pkg_stdout, pkg_stderr)
					if not pkg_success then
						utils.progress_end(essential_progress, false, pkg_stderr)
						return
					end

					utils.progress_end(essential_progress, true)

					-- Update remote plugins asynchronously
					utils.notify("Updating remote plugins...", vim.log.levels.INFO)
					local update_cmd =
						string.format("NVIM_PYTHON3_HOST_PROG=%s nvim --headless +UpdateRemotePlugins +qa", python_path)

					utils.async_system_call(update_cmd, function(update_success)
						if update_success then
							utils.notify("Remote plugins updated!", vim.log.levels.INFO)
						end

						-- Continue with project type selection
						vim.schedule(function()
							continue_after_venv_creation(venv_path, python_path)
						end)
					end, { env = { NVIM_PYTHON3_HOST_PROG = python_path } })
				end, { cwd = current_cwd })
			end, { cwd = current_cwd })
		end)
	else
		-- Venv already exists, continue with setup
		continue_after_venv_creation(venv_path, python_path)
	end
end

-- Continue setup after project type selection
function M.continue_setup(template, python_path, venv_path)
	vim.notify("Setting up " .. template.name .. " environment with Python: " .. python_path)

	-- Get current working directory
	local cwd = utils.get_project_paths()

	-- Set Python host
	vim.g.python3_host_prog = python_path

	-- Install packages
	-- Check for uv in venv first, then system
	local venv_bin = venv_path .. "/bin"
	local has_uv = vim.fn.executable(venv_bin .. "/uv") == 1 or vim.fn.executable("uv") == 1

	-- Check and install essential packages
	local missing_essential = M.check_missing_packages(python_path, template.essential)
	if #missing_essential > 0 then
		vim.notify("Installing essential packages: " .. table.concat(missing_essential, ", "))
		M.install_packages_async(missing_essential, cwd, python_path, has_uv, function(success)
			if success then
				-- Continue with optional packages
				M.check_and_install_optional(template, python_path, venv_path, cwd, has_uv)
			else
				vim.notify("Failed to install essential packages", vim.log.levels.ERROR)
			end
		end)
	else
		vim.notify("Essential packages already installed", vim.log.levels.INFO)
		-- Continue with optional packages
		M.check_and_install_optional(template, python_path, venv_path, cwd, has_uv)
	end
end

-- Check and install optional packages
function M.check_and_install_optional(template, python_path, venv_path, cwd, has_uv)
	if #template.optional > 0 then
		local missing_optional = M.check_missing_packages(python_path, template.optional)
		if #missing_optional > 0 then
			vim.notify(#missing_optional .. " project packages missing: " .. table.concat(missing_optional, ", "))
			utils.better_select(
				"Project packages:",
				{ "Install now", "Skip installation", "Show missing packages" },
				function(item)
					if item == "Install now" then
						M.install_packages_async(missing_optional, cwd, python_path, has_uv, function(success)
							-- Only complete setup after installation finishes
							if success then
								M.complete_setup(python_path)
							else
								vim.notify("Setup incomplete due to installation errors", vim.log.levels.WARN)
							end
						end)
					elseif item == "Show missing packages" then
						vim.notify("Missing: " .. table.concat(missing_optional, ", "), vim.log.levels.INFO)
						-- Don't complete setup if just showing packages
					else
						-- Skip installation
						M.complete_setup(python_path)
					end
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

	utils.notify("Setup complete!", vim.log.levels.INFO, "Success", "success")
	utils.notify(
		"Everything is configured! Please restart Neovim once to activate Molten.",
		vim.log.levels.INFO,
		"Ready",
		"success"
	)
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
	local cwd = utils.get_project_paths()
	local install_cmd
	if has_uv then
		install_cmd = string.format("cd %s && uv pip install %s", cwd, table.concat(packages, " "))
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
function M.install_packages_async(packages, cwd, python_path, has_uv, callback)
	utils.notify("Installing packages in background...", vim.log.levels.INFO)
	utils.notify("You can continue working. Check :messages for progress.", vim.log.levels.INFO)

	-- Build install command
	local cmd
	if has_uv then
		cmd = "uv pip install " .. table.concat(packages, " ")
	else
		cmd = python_path .. " -m pip install " .. table.concat(packages, " ")
	end

	local progress_id = utils.progress_start("Installing " .. #packages .. " packages")

	-- Run installation asynchronously
	local job_id = utils.async_system_call(cmd, function(success, stdout, stderr, exit_code)
		if success then
			utils.progress_end(progress_id, true, "Packages installed successfully!")
		else
			utils.progress_end(progress_id, false, "Some packages failed to install")
			-- Log the error details
			if stderr and stderr ~= "" then
				utils.notify("Installation errors: " .. stderr, vim.log.levels.WARN)
			end
		end

		-- Call the callback if provided
		if callback then
			callback(success)
		end
	end, { cwd = cwd })

	return job_id
end

return M
