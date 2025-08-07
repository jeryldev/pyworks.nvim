-- pyworks.nvim - Commands module
-- Defines all user commands

local M = {}
local utils = require("pyworks.utils")

-- Helper function to check if we're in a valid Python project
local function check_project_state()
	local cwd, venv_path = utils.get_project_paths()
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
		-- Basic validation
		local cwd, venv_path = utils.get_project_paths()
		if cwd == vim.fn.expand("~") then
			vim.notify("Warning: Running PyworksSetup in home directory!", vim.log.levels.WARN)
			utils.better_select("Home directory project:", { "Create Python project here", "Cancel" }, function(item)
				if item == "Create Python project here" then
					setup.setup_project()
				end
			end)
		else
			setup.setup_project()
		end
	end, {
		desc = "Setup Python project environment (choose type interactively)",
	})

	-- Convenience command for web development
	vim.api.nvim_create_user_command("PyworksWeb", function()
		-- Basic validation
		local cwd, venv_path = utils.get_project_paths()
		if cwd == vim.fn.expand("~") then
			vim.notify("Warning: Running PyworksWeb in home directory!", vim.log.levels.WARN)
		end

		vim.g._pyworks_project_type = 2 -- Web Development
		setup.setup_project()
		vim.g._pyworks_project_type = nil
	end, {
		desc = "Quick setup for web development (FastAPI/Flask/Django)",
	})

	-- Alias for data science (backwards compatibility)
	vim.api.nvim_create_user_command("PyworksData", function()
		-- Basic validation
		local cwd, venv_path = utils.get_project_paths()
		if cwd == vim.fn.expand("~") then
			vim.notify("Warning: Running PyworksData in home directory!", vim.log.levels.WARN)
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

	-- Debug command to check Python host
	vim.api.nvim_create_user_command("PyworksDebug", function()
		local cwd, venv_path = utils.get_project_paths()
		local python_path = venv_path .. "/bin/python3"

		vim.notify("=== Pyworks Debug Info ===", vim.log.levels.INFO)
		local cwd = utils.get_project_paths()
		vim.notify("Current directory: " .. cwd, vim.log.levels.INFO)
		vim.notify("Expected venv path: " .. venv_path, vim.log.levels.INFO)
		vim.notify("Venv exists: " .. (vim.fn.isdirectory(venv_path) == 1 and "Yes" or "No"), vim.log.levels.INFO)
		vim.notify("Expected Python: " .. python_path, vim.log.levels.INFO)
		vim.notify("Current python3_host_prog: " .. (vim.g.python3_host_prog or "not set"), vim.log.levels.INFO)
		vim.notify(
			"PATH contains .venv/bin: " .. (vim.env.PATH:match(vim.pesc(venv_path .. "/bin")) and "Yes" or "No"),
			vim.log.levels.INFO
		)
		vim.notify(
			"jupytext executable: " .. (vim.fn.executable("jupytext") == 1 and "Found" or "Not found"),
			vim.log.levels.INFO
		)

		-- Try to manually set it
		if vim.fn.isdirectory(venv_path) == 1 then
			vim.g.python3_host_prog = python_path
			local venv_bin = venv_path .. "/bin"
			if not vim.env.PATH:match(vim.pesc(venv_bin)) then
				vim.env.PATH = venv_bin .. ":" .. vim.env.PATH
			end
			vim.notify("Manually set Python host and PATH", vim.log.levels.INFO)
		end
	end, {
		desc = "Debug pyworks configuration",
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

		local cwd, venv_path = utils.get_project_paths()
		
		-- Debug output
		utils.notify("Working in: " .. cwd, vim.log.levels.INFO)
		utils.notify("Venv path: " .. venv_path, vim.log.levels.INFO)
		
		local python_path = venv_path .. "/bin/python3"
		
		-- Try python3 first, then python
		if vim.fn.executable(python_path) ~= 1 then
			python_path = venv_path .. "/bin/python"
			if vim.fn.executable(python_path) ~= 1 then
				vim.notify("Python not found in virtual environment!", vim.log.levels.ERROR)
				vim.notify("Run :PyworksSetup to fix the environment.", vim.log.levels.INFO)
				return
			end
		end

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
		setup.install_packages_async(vim.split(packages, " "), cwd, python_path, has_uv)
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

	-- Fix notebook metadata command
	vim.api.nvim_create_user_command("PyworksFixNotebook", function(opts)
		local filepath = opts.args ~= "" and opts.args or vim.fn.expand("%:p")
		if not filepath:match("%.ipynb$") then
			vim.notify("Not a notebook file: " .. filepath, vim.log.levels.ERROR)
			return
		end
		
		local fixer = require("pyworks.jupytext")
		local fixed = fixer.fix_notebook_metadata(filepath)
		if fixed then
			vim.notify("Fixed notebook metadata: " .. vim.fn.fnamemodify(filepath, ":t"), vim.log.levels.INFO)
			vim.notify("Please reopen the file to load with fixed metadata", vim.log.levels.INFO)
		else
			vim.notify("Notebook already has proper metadata: " .. vim.fn.fnamemodify(filepath, ":t"), vim.log.levels.INFO)
		end
	end, {
		nargs = "?",
		complete = "file",
		desc = "Fix Jupyter notebook metadata for Python",
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
		local cwd, venv_path = utils.get_project_paths()
		if vim.fn.isdirectory(venv_path) == 0 then
			vim.notify("No virtual environment found!", vim.log.levels.ERROR)
			utils.better_select("Virtual environment required:", { "Run PyworksSetup", "Cancel" }, function(item)
				if item == "Run PyworksSetup" then
					vim.g._pyworks_project_type = 1 -- Data Science
					setup.setup_project()
					vim.g._pyworks_project_type = nil
				end
			end)
			return
		end

		-- Check if setup is needed for Python notebooks
		if language:lower() == "python" then
			local needs_setup, reason = setup.is_setup_needed()

			if needs_setup then
				vim.notify("Project setup needed: " .. reason, vim.log.levels.WARN)
				utils.better_select(
					"Setup required:",
					{ "Run PyworksSetup first", "Continue anyway", "Cancel" },
					function(item)
						if item == "Run PyworksSetup first" then
							-- Set type to data science for notebook creation
							vim.g._pyworks_project_type = 1
							setup.setup_project()
							vim.g._pyworks_project_type = nil
							-- Wait and then create notebook
							vim.defer_fn(function()
								notebooks.create_notebook(filename, language)
							end, 1000)
						elseif item == "Continue anyway" then
							-- Continue anyway - check jupytext
							if vim.fn.executable("jupytext") == 0 then
								vim.notify("jupytext not found!", vim.log.levels.ERROR)
								vim.notify(
									"Run :PyworksSetup and choose 'Data Science' to install it.",
									vim.log.levels.INFO
								)
								return
							end
							notebooks.create_notebook(filename, language)
						end
						-- choice == 3 or nil means cancel
					end
				)
				return
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
		if opts.args == "" then
			vim.notify("Usage: :PWNewNotebook <filename> [language]", vim.log.levels.ERROR)
			return
		end
		vim.cmd("PyworksNewNotebook " .. opts.args)
	end, { nargs = "*", desc = "Alias for PyworksNewNotebook" })
	
	-- Import analysis commands
	vim.api.nvim_create_user_command("PyworksAnalyzeImports", function()
		local detector = require("pyworks.package-detector")
		local result = detector.analyze_buffer()
		if result and #result.missing == 0 and #result.compatibility == 0 then
			utils.notify("✓ All imported packages are available!", vim.log.levels.INFO)
		end
	end, {
		desc = "Analyze Python imports and check for missing packages",
	})
	
	vim.api.nvim_create_user_command("PyworksInstallSuggested", function()
		local detector = require("pyworks.package-detector")
		detector.install_suggested()
	end, {
		desc = "Install packages suggested by import analysis",
	})
	
	-- Kernel management commands
	vim.api.nvim_create_user_command("PyworksCheckKernel", function()
		local kernel_mgr = require("pyworks.kernel-manager")
		local success, kernel_name = kernel_mgr.ensure_project_kernel()
		if success then
			utils.notify("✓ Project kernel ready: " .. kernel_name, vim.log.levels.INFO)
			utils.notify("This kernel uses: " .. vim.fn.getcwd() .. "/.venv/bin/python", vim.log.levels.INFO)
		else
			utils.notify("⚠️ Kernel issue: " .. kernel_name, vim.log.levels.WARN)
			utils.notify("Run :PyworksSetup to fix this", vim.log.levels.INFO)
		end
	end, {
		desc = "Check and ensure project-specific Jupyter kernel exists",
	})
	
	vim.api.nvim_create_user_command("PyworksListKernels", function()
		local kernel_mgr = require("pyworks.kernel-manager")
		local kernels = kernel_mgr.list_kernels()
		if #kernels == 0 then
			utils.notify("No Jupyter kernels found", vim.log.levels.WARN)
		else
			utils.notify("Available Jupyter kernels:", vim.log.levels.INFO)
			for _, kernel in ipairs(kernels) do
				local is_project = kernel.name == vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
				local marker = is_project and " [PROJECT]" or ""
				utils.notify("  • " .. kernel.display .. " (" .. kernel.name .. ")" .. marker, vim.log.levels.INFO)
			end
		end
	end, {
		desc = "List all available Jupyter kernels",
	})
	
	
	-- Check image support
	vim.api.nvim_create_user_command("PyworksCheckImages", function()
		utils.notify("=== Image Support Check ===", vim.log.levels.INFO)
		
		-- Check terminal
		local term = vim.env.TERM or ""
		local kitty_id = vim.env.KITTY_WINDOW_ID
		local ghostty = vim.env.GHOSTTY_RESOURCES_DIR or vim.env.TERM_PROGRAM == "ghostty"
		local wezterm = vim.env.WEZTERM_EXECUTABLE
		local iterm = vim.env.ITERM_PROFILE
		
		if kitty_id then
			utils.notify("✓ Kitty terminal detected - images should work!", vim.log.levels.INFO)
		elseif ghostty then
			utils.notify("✓ Ghostty terminal detected - images should work!", vim.log.levels.INFO)
		elseif wezterm then
			utils.notify("⚠️ WezTerm detected - limited image support", vim.log.levels.WARN)
			utils.notify("For best results, use Kitty or Ghostty terminal", vim.log.levels.INFO)
		elseif iterm then
			utils.notify("⚠️ iTerm2 detected - limited image support", vim.log.levels.WARN)
			utils.notify("For best results, use Kitty or Ghostty terminal", vim.log.levels.INFO)
		else
			utils.notify("✗ Terminal does not support images: " .. term, vim.log.levels.ERROR)
			utils.notify("Images require Kitty or Ghostty terminal", vim.log.levels.INFO)
			utils.notify("Install Ghostty from: https://ghostty.org", vim.log.levels.INFO)
		end
		
		-- Check image.nvim
		local has_image = pcall(require, "image")
		if has_image then
			utils.notify("✓ image.nvim is installed", vim.log.levels.INFO)
		else
			utils.notify("✗ image.nvim not found", vim.log.levels.ERROR)
		end
		
		-- Check Molten configuration
		utils.notify("Molten image provider: " .. tostring(vim.g.molten_image_provider), vim.log.levels.INFO)
		utils.notify("Molten image location: " .. tostring(vim.g.molten_image_location), vim.log.levels.INFO)
		utils.notify("Molten virt_text_output: " .. tostring(vim.g.molten_virt_text_output), vim.log.levels.INFO)
		
		-- Provide help
		if not kitty_id then
			utils.notify("\nTo enable image support:", vim.log.levels.INFO)
			utils.notify("1. Install Kitty: brew install --cask kitty", vim.log.levels.INFO)
			utils.notify("2. Launch Neovim from Kitty terminal", vim.log.levels.INFO)
			utils.notify("3. Images will display inline in notebooks", vim.log.levels.INFO)
		end
	end, {
		desc = "Check if terminal supports inline images",
	})
end

return M
