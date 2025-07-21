-- pyworks.nvim - Commands module
-- Defines all user commands

local M = {}

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
		vim.g._pyworks_project_type = 2 -- Web Development
		setup.setup_project()
		vim.g._pyworks_project_type = nil
	end, {
		desc = "Quick setup for web development (FastAPI/Flask/Django)",
	})

	-- Alias for data science (backwards compatibility)
	vim.api.nvim_create_user_command("PyworksData", function()
		vim.g._pyworks_project_type = 1 -- Data Science
		setup.setup_project()
		vim.g._pyworks_project_type = nil
	end, {
		desc = "Quick setup for data science/notebooks",
	})

	-- Check environment
	vim.api.nvim_create_user_command("PyworksCheck", function()
		diagnostics.check_environment()
	end, {
		desc = "Check Python environment installation and diagnostics",
	})

	-- Install packages
	vim.api.nvim_create_user_command("PyworksInstall", function(opts)
		local packages = opts.args
		if packages == "" then
			vim.notify("Usage: :PyworksInstall <package1> [package2] ...", vim.log.levels.WARN)
			vim.notify("Example: :PyworksInstall scikit-learn keras", vim.log.levels.INFO)
			vim.notify("Run :PyworksPackages to see common packages", vim.log.levels.INFO)
			return
		end

		local venv_path = vim.fn.getcwd() .. "/.venv"
		local python_path = venv_path .. "/bin/python3"

		if vim.fn.isdirectory(venv_path) == 0 then
			vim.notify("No .venv found. Run :PyworksSetup first.", vim.log.levels.ERROR)
			return
		end

		local has_uv = vim.fn.executable("uv") == 1
		setup.install_packages_async(vim.split(packages, " "), vim.fn.getcwd(), python_path, has_uv)
	end, {
		nargs = "+",
		desc = "Install specific Python packages in project environment",
	})

	-- Show common packages
	vim.api.nvim_create_user_command("PyworksPackages", function()
		diagnostics.show_packages()
	end, {
		desc = "Show common Python packages for data science and web development",
	})

	-- Show environment status
	vim.api.nvim_create_user_command("PyworksEnv", function()
		diagnostics.show_env_status()
	end, {
		desc = "Show Python environment status",
	})

	-- Create new notebook
	vim.api.nvim_create_user_command("PyworksNew", function(opts)
		local args = vim.split(opts.args, " ")
		local filename = args[1] or "untitled.ipynb"
		local language = args[2] or "python"

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
		end

		notebooks.create_notebook(filename, language)
	end, {
		nargs = "*",
		desc = "Create new Jupyter notebook: :PyworksNew [filename] [language]",
	})

	-- Shorter aliases (optional)
	vim.api.nvim_create_user_command("PWSetup", function()
		vim.cmd("PyworksSetup")
	end, { desc = "Alias for PyworksSetup" })
	vim.api.nvim_create_user_command("PWCheck", function()
		vim.cmd("PyworksCheck")
	end, { desc = "Alias for PyworksCheck" })
	vim.api.nvim_create_user_command("PWInstall", function(opts)
		vim.cmd("PyworksInstall " .. opts.args)
	end, { nargs = "+", desc = "Alias for PyworksInstall" })
	vim.api.nvim_create_user_command("PWNew", function(opts)
		vim.cmd("PyworksNew " .. opts.args)
	end, { nargs = "*", desc = "Alias for PyworksNew" })
end

return M

