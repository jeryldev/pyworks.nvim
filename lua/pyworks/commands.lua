-- pyworks.nvim - Commands module
-- Defines all user commands

local M = {}

-- Helper function to check if we're in a valid Python project
local function check_project_state()
	local venv_path = vim.fn.getcwd() .. "/.venv"
	local has_venv = vim.fn.isdirectory(venv_path) == 1
	local python_path = venv_path .. "/bin/python3"
	local has_python_host = vim.g.python3_host_prog == python_path

	return {
		has_venv = has_venv,
		venv_path = venv_path,
		python_path = python_path,
		has_python_host = has_python_host,
		is_configured = has_venv and has_python_host,
	}
end

function M.setup()
	-- No setup needed for commands yet
end

function M.create_commands()
	local setup = require("pyworks.setup")
	local diagnostics = require("pyworks.diagnostics")
	local notebooks = require("pyworks.notebooks")

	-- Main setup command
	vim.api.nvim_create_user_command("PyworksSetup", function()
		setup.setup_project()
	end, {
		desc = "Setup Python project environment (choose type interactively)",
	})

	-- Convenience command for web development
	vim.api.nvim_create_user_command("PyworksWeb", function()
		-- Check if already in a Python project
		local venv_path = vim.fn.getcwd() .. "/.venv"
		if vim.fn.isdirectory(venv_path) == 1 then
			local choice =
				vim.fn.confirm("Virtual environment already exists. Continue with web setup?", "&Yes\n&No", 1)
			if choice ~= 1 then
				return
			end
		end

		vim.g._pyworks_project_type = 2 -- Web Development
		setup.setup_project()
		vim.g._pyworks_project_type = nil
	end, {
		desc = "Quick setup for web development (FastAPI/Flask/Django)",
	})

	-- Alias for data science (backwards compatibility)
	vim.api.nvim_create_user_command("PyworksData", function()
		-- Check if already in a Python project
		local venv_path = vim.fn.getcwd() .. "/.venv"
		if vim.fn.isdirectory(venv_path) == 1 then
			local choice =
				vim.fn.confirm("Virtual environment already exists. Continue with data science setup?", "&Yes\n&No", 1)
			if choice ~= 1 then
				return
			end
		end

		vim.g._pyworks_project_type = 1 -- Data Science
		setup.setup_project()
		vim.g._pyworks_project_type = nil
	end, {
		desc = "Quick setup for data science/notebooks",
	})

	-- Check environment
	vim.api.nvim_create_user_command("PyworksCheckEnvironment", function()
		diagnostics.check_environment()
	end, {
		desc = "Check Python environment installation and diagnostics",
	})

	-- Install packages
	vim.api.nvim_create_user_command("PyworksInstallPackages", function(opts)
		local packages = opts.args
		if packages == "" then
			vim.notify("Usage: :PyworksInstallPackages <package1> [package2] ...", vim.log.levels.WARN)
			vim.notify("Example: :PyworksInstallPackages scikit-learn keras", vim.log.levels.INFO)
			vim.notify("Run :PyworksBrowsePackages to see common packages", vim.log.levels.INFO)
			return
		end

		local venv_path = vim.fn.getcwd() .. "/.venv"
		local python_path = venv_path .. "/bin/python3"

		if vim.fn.isdirectory(venv_path) == 0 then
			vim.notify("No virtual environment found!", vim.log.levels.ERROR)
			vim.notify("Run :PyworksSetup first to create a virtual environment.", vim.log.levels.INFO)
			return
		end

		-- Check if Python host is configured
		if vim.g.python3_host_prog ~= python_path then
			vim.notify("Python host not configured for this project.", vim.log.levels.WARN)
			vim.notify("Run :PyworksSetup to configure the environment.", vim.log.levels.INFO)
		end

		local has_uv = vim.fn.executable("uv") == 1
		setup.install_packages_async(vim.split(packages, " "), vim.fn.getcwd(), python_path, has_uv)
	end, {
		nargs = "+",
		desc = "Install specific Python packages in project environment",
	})

	-- Show common packages
	vim.api.nvim_create_user_command("PyworksBrowsePackages", function()
		diagnostics.show_packages()
	end, {
		desc = "Show common Python packages for data science and web development",
	})

	-- Show environment status
	vim.api.nvim_create_user_command("PyworksShowEnvironment", function()
		diagnostics.show_env_status()
	end, {
		desc = "Show Python environment status",
	})

	-- Create new notebook
	vim.api.nvim_create_user_command("PyworksNewNotebook", function(opts)
		local args = vim.split(opts.args, " ")
		local filename = args[1]
		local language = args[2] or "python"
		
		-- Validate filename is provided
		if not filename or filename == "" then
			vim.notify("Usage: :PyworksNewNotebook <filename> [language]", vim.log.levels.ERROR)
			vim.notify("Example: :PyworksNewNotebook analysis.ipynb", vim.log.levels.INFO)
			vim.notify("Languages: python (default), julia, r", vim.log.levels.INFO)
			return
		end

		-- Validate language
		local valid_languages = { python = true, julia = true, r = true }
		if not valid_languages[language:lower()] then
			vim.notify("Invalid language: " .. language, vim.log.levels.ERROR)
			vim.notify("Supported languages: python, julia, r", vim.log.levels.INFO)
			return
		end

		-- Check if virtual environment exists
		local venv_path = vim.fn.getcwd() .. "/.venv"
		if vim.fn.isdirectory(venv_path) == 0 then
			vim.notify("No virtual environment found!", vim.log.levels.ERROR)
			local choice = vim.fn.confirm("Run :PyworksSetup to create one?", "&Yes\n&No", 1)
			if choice == 1 then
				vim.g._pyworks_project_type = 1 -- Data Science
				setup.setup_project()
				vim.g._pyworks_project_type = nil
			end
			return
		end

		-- Check if setup is needed for Python notebooks
		if language:lower() == "python" then
			local needs_setup, reason = setup.is_setup_needed()

			if needs_setup then
				local msg = string.format("Project setup needed: %s\n\nRun :PyworksSetup first?", reason)
				local choice = vim.fn.confirm(msg, "&Yes\n&No\n&Cancel", 1)

				if choice == 1 then
					-- Set type to data science for notebook creation
					vim.g._pyworks_project_type = 1
					setup.setup_project()
					vim.g._pyworks_project_type = nil
					-- Wait and then create notebook
					vim.defer_fn(function()
						notebooks.create_notebook(filename, language)
					end, 1000)
					return
				elseif choice == 3 then
					return
				end
			end

			-- Check if jupytext is available
			if vim.fn.executable("jupytext") == 0 then
				vim.notify("jupytext not found!", vim.log.levels.ERROR)
				vim.notify("Run :PyworksSetup and choose 'Data Science' to install it.", vim.log.levels.INFO)
				return
			end
		end

		notebooks.create_notebook(filename, language)
	end, {
		nargs = "*",
		desc = "Create new Jupyter notebook: :PyworksNewNotebook [filename] [language]",
	})

	-- Shorter aliases (optional)
	vim.api.nvim_create_user_command("PWSetup", function()
		vim.cmd("PyworksSetup")
	end, { desc = "Alias for PyworksSetup" })
	vim.api.nvim_create_user_command("PWCheck", function()
		vim.cmd("PyworksCheckEnvironment")
	end, { desc = "Alias for PyworksCheckEnvironment" })
	vim.api.nvim_create_user_command("PWInstall", function(opts)
		vim.cmd("PyworksInstallPackages " .. opts.args)
	end, { nargs = "+", desc = "Alias for PyworksInstallPackages" })
	vim.api.nvim_create_user_command("PWNewNotebook", function(opts)
		vim.cmd("PyworksNewNotebook " .. opts.args)
	end, { nargs = "*", desc = "Alias for PyworksNewNotebook" })
end

return M
