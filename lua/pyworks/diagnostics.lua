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

	-- Check if Python exists
	if python_host ~= "not set" then
		local exists = vim.fn.executable(python_host) == 1
		table.insert(diagnostics, "Python exists: " .. (exists and "✓" or "✗"))
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
	local package_categories = {
		["🔬 Data Science Essentials"] = {
			"numpy",
			"pandas",
			"matplotlib",
			"seaborn",
			"scipy",
			"statsmodels",
			"scikit-learn",
			"jupyter",
			"notebook",
		},
		["🤖 Machine Learning"] = {
			"tensorflow",
			"keras",
			"torch",
			"torchvision",
			"xgboost",
			"lightgbm",
			"catboost",
			"optuna",
			"mlflow",
		},
		["📊 Visualization"] = {
			"plotly",
			"bokeh",
			"altair",
			"holoviews",
			"dash",
			"streamlit",
			"gradio",
			"panel",
		},
		["🗄️ Data Engineering"] = {
			"dask",
			"ray",
			"vaex",
			"polars",
			"pyarrow",
			"sqlalchemy",
			"pymongo",
			"redis-py",
		},
		["🌐 Web & APIs"] = {
			"requests",
			"httpx",
			"beautifulsoup4",
			"scrapy",
			"fastapi",
			"flask",
			"django",
			"aiohttp",
		},
		["🔧 Utilities"] = {
			"tqdm",
			"rich",
			"typer",
			"click",
			"python-dotenv",
			"pydantic",
			"pytest",
			"black",
			"ruff",
		},
		["📚 NLP & Text"] = {
			"nltk",
			"spacy",
			"transformers",
			"langchain",
			"openai",
			"anthropic",
			"gensim",
			"textblob",
		},
		["🖼️ Computer Vision"] = {
			"opencv-python",
			"pillow",
			"scikit-image",
			"albumentations",
			"detectron2",
			"ultralytics",
			"mediapipe",
		},
	}

	local lines = { "=== Common Python Packages ===", "" }
	table.insert(lines, "Install with: :PyworksInstall <package-name>")
	table.insert(lines, "Example: :PyworksInstall pandas matplotlib scikit-learn")
	table.insert(lines, "")

	for category, packages in pairs(package_categories) do
		table.insert(lines, category)
		for _, pkg in ipairs(packages) do
			table.insert(lines, "  • " .. pkg)
		end
		table.insert(lines, "")
	end

	table.insert(lines, "💡 Tips:")
	table.insert(lines, "- You can install ANY package from PyPI, not just these")
	table.insert(lines, "- Install multiple at once: :PyworksInstall pandas numpy matplotlib")
	table.insert(lines, "- Check installed: :PyworksCheck")

	M.show_in_float(lines, "Python Packages")
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
			print("- Installing packages with pip (use :PyworksInstall instead)")
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

