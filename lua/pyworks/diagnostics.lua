-- pyworks.nvim - Diagnostics module
-- Handles environment checking and package display

local M = {}

local setup = require("pyworks.setup")

-- Check environment and show diagnostics
function M.check_environment()
	local diagnostics = {}

	-- Check Python host
	table.insert(diagnostics, "=== Pyworks Diagnostics ===")
	table.insert(diagnostics, "")

	local python_host = vim.g.python3_host_prog or "not set"
	table.insert(diagnostics, "Python3 host: " .. python_host)

	-- Check if Python exists and has pynvim
	if python_host ~= "not set" then
		local exists = vim.fn.executable(python_host) == 1
		table.insert(diagnostics, "Python exists: " .. (exists and "✓" or "✗"))
		
		if exists then
			-- Check if pynvim is installed
			local pynvim_check = vim.fn.system(python_host .. " -c 'import pynvim; print(pynvim.__version__)' 2>&1")
			if vim.v.shell_error == 0 then
				local version = pynvim_check:gsub("\n", "")
				table.insert(diagnostics, "pynvim installed: ✓ (version " .. version .. ")")
			else
				table.insert(diagnostics, "pynvim installed: ✗ (required for Molten)")
				table.insert(diagnostics, "  Fix: " .. python_host .. " -m pip install pynvim")
			end
		end
	end

	-- Check virtual environment
	local venv_python = vim.fn.getcwd() .. "/.venv/bin/python3"
	local has_venv = vim.fn.executable(venv_python) == 1
	table.insert(diagnostics, "Project venv: " .. (has_venv and "✓ " .. venv_python or "✗ not found"))

	-- Check current Python
	local current_python = vim.fn.exepath("python3")
	table.insert(diagnostics, "Active Python: " .. current_python)

	-- Check for Python host mismatch
	if has_venv and python_host ~= venv_python then
		table.insert(diagnostics, "")
		table.insert(diagnostics, "⚠️  Python host mismatch!")
		table.insert(diagnostics, "   Run :PyworksSetup and restart Neovim")
	end

	-- Check if Molten commands exist
	table.insert(diagnostics, "")
	table.insert(diagnostics, "Molten Commands:")
	local commands = { "MoltenInit", "MoltenEvaluateCell", "MoltenReevaluateCell", "MoltenInfo" }
	for _, cmd in ipairs(commands) do
		local exists = vim.fn.exists(":" .. cmd) == 2
		table.insert(diagnostics, "  " .. cmd .. ": " .. (exists and "✓" or "✗"))
	end

	-- Check required Python packages
	table.insert(diagnostics, "")
	table.insert(diagnostics, "Python Packages:")

	local packages = {
		-- Essential
		"pynvim",
		"jupyter_client",
		"ipykernel",
		"jupytext",
		-- Data Science
		"numpy",
		"pandas",
		"matplotlib",
		"scikit-learn",
	}

	-- Use the project's Python for checking packages
	local check_python = venv_python
	if not has_venv then
		check_python = current_python
	end

	for _, pkg in ipairs(packages) do
		-- Get the import name (handle special cases)
		local import_name = setup.package_map[pkg] or pkg:gsub("-", "_")

		local check_cmd = string.format(
			"%s -c 'import %s; print(%s.__version__)' 2>/dev/null",
			check_python,
			import_name,
			import_name
		)
		local version = vim.fn.system(check_cmd):gsub("\n", "")
		if vim.v.shell_error == 0 then
			table.insert(diagnostics, "  " .. pkg .. ": ✓ " .. version)
		else
			-- Try without version (some packages don't have __version__)
			local check_cmd_simple = string.format("%s -c 'import %s' 2>/dev/null", check_python, import_name)
			if vim.fn.system(check_cmd_simple) == "" and vim.v.shell_error == 0 then
				table.insert(diagnostics, "  " .. pkg .. ": ✓ (no version info)")
			else
				table.insert(diagnostics, "  " .. pkg .. ": ✗ not installed")
			end
		end
	end

	-- Check remote plugin registration
	table.insert(diagnostics, "")
	local rplugin_file = vim.fn.expand("~/.local/share/nvim/rplugin.vim")
	if vim.fn.filereadable(rplugin_file) == 1 then
		local content = vim.fn.readfile(rplugin_file)
		local has_molten = false
		for _, line in ipairs(content) do
			if line:match("molten") then
				has_molten = true
				break
			end
		end
		table.insert(
			diagnostics,
			"Remote plugin registration: " .. (has_molten and "✓ molten registered" or "✗ molten not found")
		)
	else
		table.insert(diagnostics, "Remote plugin registration: ✗ rplugin.vim not found")
	end

	-- Display diagnostics in floating window
	M.show_in_float(diagnostics, "Pyworks Diagnostics")
end

-- Show common packages
function M.show_packages()
	local utils = require("pyworks.utils")
	local config = require("pyworks.config")

	local package_categories = {
		{
			name = "🔬 Data Science Essentials",
			packages = {
				{ name = "numpy", desc = "Numerical computing with arrays" },
				{ name = "pandas", desc = "Data manipulation and analysis" },
				{ name = "matplotlib", desc = "Plotting and visualization" },
				{ name = "seaborn", desc = "Statistical data visualization" },
				{ name = "scipy", desc = "Scientific computing tools" },
				{ name = "statsmodels", desc = "Statistical modeling" },
				{ name = "scikit-learn", desc = "Machine learning library" },
				{ name = "jupyter", desc = "Interactive notebooks" },
				{ name = "notebook", desc = "Jupyter notebook interface" },
			},
		},
		{
			name = "🤖 Machine Learning",
			packages = {
				{ name = "tensorflow", desc = "Deep learning framework" },
				{ name = "torch", desc = "PyTorch deep learning" },
				{ name = "transformers", desc = "State-of-the-art NLP" },
				{ name = "xgboost", desc = "Gradient boosting" },
				{ name = "lightgbm", desc = "Fast gradient boosting" },
				{ name = "catboost", desc = "Gradient boosting with categorical features" },
				{ name = "optuna", desc = "Hyperparameter optimization" },
				{ name = "mlflow", desc = "ML lifecycle platform" },
			},
		},
		{
			name = "📊 Visualization",
			packages = {
				{ name = "plotly", desc = "Interactive graphing" },
				{ name = "bokeh", desc = "Interactive visualization" },
				{ name = "altair", desc = "Declarative visualization" },
				{ name = "dash", desc = "Web apps for Python" },
				{ name = "streamlit", desc = "Data apps framework" },
				{ name = "gradio", desc = "ML web demos" },
			},
		},
		{
			name = "🌐 Web Development",
			packages = {
				{ name = "fastapi", desc = "Modern web API framework" },
				{ name = "flask", desc = "Micro web framework" },
				{ name = "django", desc = "Full-stack web framework" },
				{ name = "requests", desc = "HTTP library" },
				{ name = "httpx", desc = "Async HTTP client" },
				{ name = "beautifulsoup4", desc = "Web scraping" },
				{ name = "uvicorn[standard]", desc = "ASGI server" },
			},
		},
		{
			name = "🛠️ Developer Tools",
			packages = {
				{ name = "pytest", desc = "Testing framework" },
				{ name = "black", desc = "Code formatter" },
				{ name = "ruff", desc = "Fast Python linter" },
				{ name = "mypy", desc = "Static type checker" },
				{ name = "rich", desc = "Rich terminal output" },
				{ name = "typer", desc = "CLI app builder" },
				{ name = "python-dotenv", desc = "Load .env files" },
				{ name = "pydantic", desc = "Data validation" },
			},
		},
	}

	-- Interactive category selection
	local category_names = {}
	for _, cat in ipairs(package_categories) do
		table.insert(category_names, cat.name)
	end
	table.insert(category_names, "📋 View All Packages")
	table.insert(category_names, "🔍 Search Package")

	utils.better_select("Browse Python packages:", category_names, function(selected)
		if not selected then
			return
		end

		if selected == "📋 View All Packages" then
			-- Show all in floating window
			local lines = { "=== Python Package Browser ===", "" }
			table.insert(lines, config.format_message("Install: :PyworksInstallPackages <package>", "info"))
			table.insert(lines, "")

			for _, category in ipairs(package_categories) do
				table.insert(lines, category.name)
				table.insert(lines, string.rep("─", 50))
				for _, pkg in ipairs(category.packages) do
					table.insert(lines, string.format("  %-20s %s", pkg.name, pkg.desc or ""))
				end
				table.insert(lines, "")
			end

			table.insert(lines, config.format_message("Tips:", "info"))
			table.insert(lines, "• Install multiple: :PyworksInstallPackages pandas numpy")
			table.insert(lines, "• Check installed: :PyworksCheckEnvironment")
			table.insert(lines, "• Install ANY PyPI package!")

			M.show_in_float(lines, "Python Packages")
		elseif selected == "🔍 Search Package" then
			-- Search functionality
			vim.ui.input({
				prompt = "Search package name: ",
			}, function(query)
				if query and query ~= "" then
					vim.cmd("PyworksInstallPackages " .. query)
				end
			end)
		else
			-- Show packages from selected category
			for _, category in ipairs(package_categories) do
				if category.name == selected then
					local items = {}

					-- Add packages with descriptions
					for _, pkg in ipairs(category.packages) do
						table.insert(items, string.format("%-20s - %s", pkg.name, pkg.desc or ""))
					end

					-- Add action items
					table.insert(items, "")
					table.insert(items, "📦 Install All " .. category.name .. " Packages")
					table.insert(items, "🔙 Back to Categories")

					utils.better_select(category.name .. " packages:", items, function(item_selected)
						if not item_selected then
							return
						end

						if item_selected == "🔙 Back to Categories" then
							M.show_packages()
							return
						elseif item_selected:match("^📦 Install All") then
							-- Install all packages in category
							local pkg_names = {}
							for _, pkg in ipairs(category.packages) do
								table.insert(pkg_names, pkg.name)
							end
							local cmd = "PyworksInstallPackages " .. table.concat(pkg_names, " ")

							vim.ui.select({ "Yes", "No" }, {
								prompt = "Install all " .. #pkg_names .. " packages?",
							}, function(confirm)
								if confirm == "Yes" then
									vim.cmd(cmd)
								end
							end)
						elseif item_selected ~= "" then
							-- Extract package name from selection
							local pkg_name = item_selected:match("^(%S+)")
							if pkg_name then
								vim.ui.input({
									prompt = "Install command: ",
									default = "PyworksInstallPackages " .. pkg_name,
								}, function(cmd)
									if cmd and cmd ~= "" then
										vim.cmd(cmd)
									end
								end)
							end
						end
					end)
					break
				end
			end
		end
	end)
end

-- Show environment status
function M.show_env_status()
	local venv_path = vim.fn.getcwd() .. "/.venv"
	local venv_python = venv_path .. "/bin/python3"

	print("=== Python Environment Status ===")
	print("")
	print("Project directory: " .. vim.fn.getcwd())
	print("Virtual env exists: " .. (vim.fn.isdirectory(venv_path) == 1 and "✓" or "✗"))
	print("")
	print("Shell Python: " .. vim.fn.exepath("python3"))
	print("Neovim Python host: " .. (vim.g.python3_host_prog or "not set"))
	print("")

	if vim.fn.isdirectory(venv_path) == 1 then
		local shell_python = vim.fn.exepath("python3")
		local activated = shell_python:match(venv_path) ~= nil

		print("Virtual env activated in shell: " .. (activated and "✓" or "✗"))

		if not activated then
			print("")
			print("⚠️  To activate in your shell, run:")
			print("   source .venv/bin/activate")
			print("")
			print("Note: This only affects:")
			print("- Running Python in the terminal")
			print("- Installing packages with pip (use :PyworksInstallPackages instead)")
			print("")
			print("Notebooks will still work correctly!")
		end
	end
end

-- Helper to show content in floating window
function M.show_in_float(lines, title)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

	local width = 70
	local height = math.min(#lines + 2, 30)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
	})

	-- Set up keymaps to close
	vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { silent = true })
	vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { silent = true })
end

return M
