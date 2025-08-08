-- Core file type detection and routing system for pyworks.nvim
-- This module is the entry point for all file handling

local M = {}

local cache = require("pyworks.core.cache")
local notifications = require("pyworks.core.notifications")
local state = require("pyworks.core.state")

-- Language detection for notebooks
local function detect_notebook_language(filepath)
	-- Try cache first
	local cached = cache.get("notebook_lang_" .. filepath)
	if cached then
		return cached
	end

	-- Read notebook metadata
	local file = io.open(filepath, "r")
	if not file then
		return "python" -- Default to Python
	end

	local content = file:read("*all")
	file:close()

	-- Try to parse as JSON
	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		return "python" -- Default if can't parse
	end

	-- Check metadata for language
	local language = "python" -- Default

	if data.metadata then
		if data.metadata.kernelspec then
			local lang = data.metadata.kernelspec.language
			if lang then
				language = lang:lower()
			end
		elseif data.metadata.language_info then
			local lang = data.metadata.language_info.name
			if lang then
				language = lang:lower()
			end
		end
	end

	-- Normalize language names
	if language == "r" then
		language = "r"
	elseif language == "julia" then
		language = "julia"
	else
		language = "python" -- Default for unknown
	end

	-- Cache the result
	cache.set("notebook_lang_" .. filepath, language)

	return language
end

-- Main file handler
function M.on_file_open(filepath)
	-- Validate and ensure absolute filepath
	if not filepath or filepath == "" then
		return
	end

	-- Ensure absolute path
	if not filepath:match("^/") then
		filepath = vim.fn.fnamemodify(filepath, ":p")
	end

	-- Skip if already processing
	if state.get("processing_" .. filepath) then
		return
	end

	state.set("processing_" .. filepath, true)

	-- Always show what file we're processing
	local notifications = require("pyworks.core.notifications")
	notifications.notify(
		string.format("🔍 Processing: %s", vim.fn.fnamemodify(filepath, ":t")),
		vim.log.levels.INFO,
		{ force = true } -- Force show even when silent
	)

	-- Detect file type
	local ext = vim.fn.fnamemodify(filepath, ":e")
	local ft = vim.bo.filetype

	-- Show that detection is happening
	local notifications = require("pyworks.core.notifications")
	if notifications.get_config().debug_mode then
		notifications.notify(
			string.format("[Detector] Processing %s (ext: %s, ft: %s)", filepath, ext, ft),
			vim.log.levels.DEBUG
		)
	end

	-- Route to appropriate handler
	if ext == "ipynb" then
		M.handle_notebook(filepath)
	elseif ext == "py" or ft == "python" then
		M.handle_python(filepath)
	elseif ext == "jl" or ft == "julia" then
		M.handle_julia(filepath)
	elseif ext == "R" or ft == "r" then
		M.handle_r(filepath)
	end

	-- Clear processing flag after a delay
	vim.defer_fn(function()
		state.set("processing_" .. filepath, nil)
	end, 100)
end

-- Handle notebook files
function M.handle_notebook(filepath)
	-- Step 1: Ensure jupytext is available
	local notebook = require("pyworks.notebook.jupytext")
	if not notebook.ensure_jupytext() then
		notifications.notify(
			"Jupytext not found. Install with: pip install jupytext",
			vim.log.levels.WARN,
			{ action_required = true }
		)
		return
	end

	-- Step 2: Detect notebook language
	local language = detect_notebook_language(filepath)

	-- Step 3: Route to language-specific handler
	if language == "julia" then
		M.handle_julia_notebook(filepath)
	elseif language == "r" then
		M.handle_r_notebook(filepath)
	else
		M.handle_python_notebook(filepath)
	end
end

-- Get available kernels dynamically
local function get_available_kernels()
	local result = vim.fn.system("jupyter kernelspec list --json 2>/dev/null")
	if vim.v.shell_error ~= 0 then
		return {}
	end

	local ok, data = pcall(vim.json.decode, result)
	if not ok or not data.kernelspecs then
		return {}
	end

	local kernels = {}
	for name, spec in pairs(data.kernelspecs) do
		if spec.spec and spec.spec.language then
			local lang = spec.spec.language:lower()
			-- Store the actual kernel name for each language
			if not kernels[lang] then
				kernels[lang] = name
			end
		end
	end

	return kernels
end

-- Cache available kernels
local cached_kernels = nil
local kernel_cache_time = 0

local function get_kernel_for_language(language, filepath)
	-- For Python, we need to match the kernel to the project's venv
	if language:lower() == "python" and filepath then
		local utils = require("pyworks.utils")
		local project_dir, venv_path = utils.get_project_paths(filepath)

		-- Debug logging (only if debug mode)
		local notifications = require("pyworks.core.notifications")
		if notifications.get_config().debug_mode then
			notifications.notify(
				string.format("Kernel selection: File=%s, Project=%s", filepath, project_dir),
				vim.log.levels.DEBUG
			)
		end

		-- Get the Python path for this project
		local python_path = venv_path .. "/bin/python"
		if vim.fn.executable(python_path) ~= 1 then
			python_path = venv_path .. "/bin/python3"
			if vim.fn.executable(python_path) ~= 1 then
				-- Try python3.12 or other versions
				python_path = venv_path .. "/bin/python3.12"
				if vim.fn.executable(python_path) ~= 1 then
					notifications.notify(
						string.format("⚠️ No Python found in venv: %s", venv_path),
						vim.log.levels.WARN,
						{ force = true }
					)
					-- Create venv if it doesn't have Python
					local python_module = require("pyworks.languages.python")
					python_module.ensure_venv(project_dir)
					-- Try again
					python_path = venv_path .. "/bin/python3"
				end
			end
		end

		-- Only show in debug mode
		if notifications.get_config().debug_mode then
			notifications.notify(
				string.format("🔍 Looking for kernel matching venv Python: %s", python_path),
				vim.log.levels.DEBUG
			)
		end

		-- Get all available kernels
		local all_kernels = get_available_kernels()

		-- Find a kernel that uses this project's Python
		local result = vim.fn.system("jupyter kernelspec list --json 2>/dev/null")
		if vim.v.shell_error == 0 then
			local ok, data = pcall(vim.json.decode, result)
			if ok and data.kernelspecs then
				for name, spec in pairs(data.kernelspecs) do
					if spec.spec and spec.spec.language and spec.spec.language:lower() == "python" then
						-- Check if this kernel uses our project's Python
						if spec.spec.argv and spec.spec.argv[1] then
							local kernel_python = spec.spec.argv[1]
							-- DON'T resolve symlinks - compare the actual paths
							-- vim.fn.resolve() is causing issues with truncated paths
							local kernel_python_to_compare = kernel_python
							local venv_python_to_compare = python_path

							-- Only show debug comparison in debug mode
							if notifications.get_config().debug_mode then
								notifications.notify(
									string.format("🔍 Kernel '%s' uses: %s", name, kernel_python_to_compare),
									vim.log.levels.DEBUG
								)
								notifications.notify(
									string.format("🔍 Project expects: %s", venv_python_to_compare),
									vim.log.levels.DEBUG
								)
							end

							-- Only match if kernel uses EXACTLY our project's Python
							local is_exact_match = (kernel_python_to_compare == venv_python_to_compare)
							if is_exact_match then
								-- Found an exact match!
								notifications.notify(
									string.format("✅ Found exact matching kernel '%s' -> %s", name, kernel_python),
									vim.log.levels.INFO,
									{ force = true } -- Force show even when silent
								)
								return name
							elseif kernel_python:match("^" .. vim.pesc(venv_path)) then
								-- Kernel is from our exact venv directory
								notifications.notify(
									string.format("✅ Found venv kernel '%s' -> %s", name, kernel_python),
									vim.log.levels.INFO,
									{ force = true } -- Force show even when silent
								)
								return name
							else
								-- Log why this kernel doesn't match
								if notifications.get_config().debug_mode then
									notifications.notify(
										string.format(
											"❌ Kernel '%s' uses %s, not %s",
											name,
											kernel_python_to_compare,
											venv_python_to_compare
										),
										vim.log.levels.DEBUG
									)
								end
							end
						end
					end
				end
			end
		end

		-- No matching kernel found - we should create one
		local notifications = require("pyworks.core.notifications")
		notifications.notify(string.format("📦 No kernel found for %s", project_dir), vim.log.levels.INFO)

		-- Create a kernel name based on the full path to ensure uniqueness
		-- Use the last two folder components for readability
		local project_name = vim.fn.fnamemodify(project_dir, ":t")
		local parent_name = vim.fn.fnamemodify(vim.fn.fnamemodify(project_dir, ":h"), ":t")

		local kernel_name
		if parent_name and parent_name ~= "" and parent_name ~= "/" and parent_name ~= "Users" then
			-- Include parent for uniqueness (e.g., "pgdaiml_simulation_notebooks")
			kernel_name = (parent_name .. "_" .. project_name):lower():gsub("[^%w_]", "_")
		else
			-- Just use the folder name
			kernel_name = project_name:lower():gsub("[^%w_]", "_")
		end

		notifications.notify(
			string.format("🔨 Creating kernel '%s' for venv: %s", kernel_name, venv_path),
			vim.log.levels.INFO
		)

		local cmd = string.format(
			"%s -m ipykernel install --user --name %s --display-name 'Python (%s)'",
			python_path,
			kernel_name,
			project_name
		)

		local output = vim.fn.system(cmd)
		if vim.v.shell_error == 0 then
			notifications.notify(
				string.format("✅ Created kernel '%s' -> %s", kernel_name, python_path),
				vim.log.levels.INFO
			)
			-- Clear kernel cache to pick up the new kernel
			cached_kernels = nil
			return kernel_name
		else
			notifications.notify(
				"❌ Failed to create kernel. Install ipykernel in the venv first.",
				vim.log.levels.WARN
			)
			return nil
		end
	else
		-- For Julia and R, use the original logic
		-- Refresh cache if older than 60 seconds
		local now = vim.loop.now()
		if not cached_kernels or (now - kernel_cache_time) > 60000 then
			cached_kernels = get_available_kernels()
			kernel_cache_time = now
		end

		-- Look up kernel for this language
		local lang = language:lower()
		local kernel = cached_kernels[lang]
		if kernel then
			local notifications = require("pyworks.core.notifications")
			notifications.notify(string.format("🎯 Using %s kernel: %s", language, kernel), vim.log.levels.INFO)
		end
		return kernel
	end
end

-- Initialize Molten automatically for the language
local function auto_init_molten(language, filepath)
	-- Check if Molten is available
	if vim.fn.exists(":MoltenInit") ~= 2 then
		local notifications = require("pyworks.core.notifications")
		notifications.notify("Molten not available - install with :Lazy load molten-nvim", vim.log.levels.WARN)
		return
	end

	-- Skip if we've already tried to initialize for this buffer
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.b[bufnr].molten_init_attempted then
		return
	end
	vim.b[bufnr].molten_init_attempted = true

	-- Show we're attempting initialization
	local notifications = require("pyworks.core.notifications")
	notifications.notify(string.format("Setting up %s kernel for execution...", language), vim.log.levels.INFO)

	-- Get the actual kernel name for this language and project
	local kernel = get_kernel_for_language(language, filepath)

	if kernel then
		-- Initialize Molten after a short delay to let environment setup complete
		vim.defer_fn(function()
			-- Try to initialize the kernel
			local ok, err = pcall(vim.cmd, "MoltenInit " .. kernel)
			if ok then
				vim.b[bufnr].molten_initialized = true

				-- Show clear notification that kernel is ready
				local notifications = require("pyworks.core.notifications")
				notifications.notify(
					string.format("✅ Molten ready with %s kernel - Use <leader>jl to run code", kernel),
					vim.log.levels.INFO
				)
			else
				-- If initialization failed, try again later or let user do it manually
				vim.b[bufnr].molten_init_attempted = false -- Allow retry
				local notifications = require("pyworks.core.notifications")
				notifications.notify(
					string.format(
						"Failed to auto-initialize kernel for %s. Press <leader>mi to initialize manually",
						language
					),
					vim.log.levels.WARN
				)
			end
		end, 200) -- Reduced to 200ms - just enough for buffer to settle
	else
		-- No kernel found for this language
		vim.b[bufnr].molten_init_attempted = false -- Allow retry
		local notifications = require("pyworks.core.notifications")
		if language == "julia" then
			notifications.notify("Julia kernel not found. Ensure IJulia is installed.", vim.log.levels.WARN)
		elseif language == "r" then
			notifications.notify("R kernel not found. Ensure IRkernel is installed.", vim.log.levels.WARN)
		else
			notifications.notify(string.format("No kernel found for %s", language), vim.log.levels.WARN)
		end
	end
end

-- Python file handler
function M.handle_python(filepath)
	-- Set up Python host for this file's project
	local init = require("pyworks.init")
	init.setup_python_host(filepath)

	-- Show project and venv detection in a single notification
	local utils = require("pyworks.utils")
	local project_dir, venv_path = utils.get_project_paths(filepath)
	local notifications = require("pyworks.core.notifications")
	
	-- Combine project and venv info
	local project_name = vim.fn.fnamemodify(project_dir, ":t")
	if vim.fn.isdirectory(venv_path) == 1 then
		notifications.notify(
			string.format("🐍 Python (%s): Using .venv", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	else
		notifications.notify(
			string.format("🐍 Python (%s): Creating .venv", project_name),
			vim.log.levels.WARN,
			{ force = true }
		)
	end

	local python = require("pyworks.languages.python")
	python.handle_file(filepath, false) -- false = not a notebook
	auto_init_molten("python", filepath)
end

-- Python notebook handler
function M.handle_python_notebook(filepath)
	-- Set up Python host for this file's project
	local init = require("pyworks.init")
	init.setup_python_host(filepath)

	-- Show project and venv detection in a single notification
	local utils = require("pyworks.utils")
	local project_dir, venv_path = utils.get_project_paths(filepath)
	local notifications = require("pyworks.core.notifications")
	
	-- Combine project and venv info for notebook
	local project_name = vim.fn.fnamemodify(project_dir, ":t")
	if vim.fn.isdirectory(venv_path) == 1 then
		notifications.notify(
			string.format("📓 Python Notebook (%s): Using .venv", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	else
		notifications.notify(
			string.format("📓 Python Notebook (%s): Creating .venv", project_name),
			vim.log.levels.WARN,
			{ force = true }
		)
	end

	local python = require("pyworks.languages.python")
	python.handle_file(filepath, true) -- true = is a notebook
	auto_init_molten("python", filepath)
end

-- Julia file handler
function M.handle_julia(filepath)
	-- Show project detection in a single notification
	local notifications = require("pyworks.core.notifications")
	local project_dir = vim.fn.fnamemodify(filepath, ":h")
	local project_name = vim.fn.fnamemodify(project_dir, ":t")
	
	-- Check for Project.toml
	if vim.fn.filereadable(project_dir .. "/Project.toml") == 1 then
		notifications.notify(
			string.format("🔶 Julia (%s): Using Project.toml", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	else
		notifications.notify(
			string.format("🔶 Julia (%s): No Project.toml", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	end

	local julia = require("pyworks.languages.julia")
	julia.handle_file(filepath, false)
	auto_init_molten("julia", filepath)
end

-- Julia notebook handler
function M.handle_julia_notebook(filepath)
	-- Show project detection in a single notification
	local notifications = require("pyworks.core.notifications")
	local project_dir = vim.fn.fnamemodify(filepath, ":h")
	local project_name = vim.fn.fnamemodify(project_dir, ":t")
	
	-- Check for Project.toml  
	if vim.fn.filereadable(project_dir .. "/Project.toml") == 1 then
		notifications.notify(
			string.format("📓 Julia Notebook (%s): Using Project.toml", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	else
		notifications.notify(
			string.format("📓 Julia Notebook (%s): No Project.toml", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	end

	local julia = require("pyworks.languages.julia")
	julia.handle_file(filepath, true)
	auto_init_molten("julia", filepath)
end

-- R file handler
function M.handle_r(filepath)
	-- Show project detection in a single notification
	local notifications = require("pyworks.core.notifications")
	local project_dir = vim.fn.fnamemodify(filepath, ":h")
	local project_name = vim.fn.fnamemodify(project_dir, ":t")
	
	-- Check for renv or .Rproj
	if vim.fn.filereadable(project_dir .. "/renv.lock") == 1 then
		notifications.notify(
			string.format("📦 R (%s): Using renv", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	elseif vim.fn.glob(project_dir .. "/*.Rproj") ~= "" then
		notifications.notify(
			string.format("📦 R (%s): Using .Rproj", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	else
		notifications.notify(
			string.format("📦 R (%s): No project file", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	end

	local r = require("pyworks.languages.r")
	r.handle_file(filepath, false)
	auto_init_molten("r", filepath)
end

-- R notebook handler
function M.handle_r_notebook(filepath)
	-- Show project detection in a single notification
	local notifications = require("pyworks.core.notifications")
	local project_dir = vim.fn.fnamemodify(filepath, ":h")
	local project_name = vim.fn.fnamemodify(project_dir, ":t")
	
	-- Check for renv or .Rproj
	if vim.fn.filereadable(project_dir .. "/renv.lock") == 1 then
		notifications.notify(
			string.format("📓 R Notebook (%s): Using renv", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	elseif vim.fn.glob(project_dir .. "/*.Rproj") ~= "" then
		notifications.notify(
			string.format("📓 R Notebook (%s): Using .Rproj", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	else
		notifications.notify(
			string.format("📓 R Notebook (%s): No project file", project_name),
			vim.log.levels.INFO,
			{ force = true }
		)
	end

	local r = require("pyworks.languages.r")
	r.handle_file(filepath, true)
	auto_init_molten("r", filepath)
end

-- Re-scan imports on file save
function M.rescan_imports(filepath)
	-- Determine language from file type
	local ext = vim.fn.fnamemodify(filepath, ":e")
	local ft = vim.bo.filetype

	local language = nil
	if ext == "ipynb" then
		language = detect_notebook_language(filepath)
	elseif ext == "py" or ft == "python" then
		language = "python"
	elseif ext == "jl" or ft == "julia" then
		language = "julia"
	elseif ext == "R" or ft == "r" then
		language = "r"
	end

	if language then
		local packages = require("pyworks.core.packages")
		packages.rescan_for_language(filepath, language)
	end
end

-- Export kernel detection for use in other modules
M.get_kernel_for_language = get_kernel_for_language

return M
