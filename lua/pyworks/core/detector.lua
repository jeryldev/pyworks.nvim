-- Core file type detection and routing system for pyworks.nvim
-- This module is the entry point for all file handling

local M = {}

local cache = require("pyworks.core.cache")
local notifications = require("pyworks.core.notifications")
local state = require("pyworks.core.state")
local utils = require("pyworks.utils")

-- Timeout constants (in milliseconds)
local KERNEL_LIST_TIMEOUT_MS = 10000 -- 10 seconds for kernel listing
local KERNEL_CREATE_TIMEOUT_MS = 30000 -- 30 seconds for kernel creation

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

	-- Pyworks only supports Python (return python for all notebooks)
	language = "python"

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

	-- Helper to ensure processing flag is always cleared (finally pattern)
	local function clear_processing_flag()
		vim.defer_fn(function()
			state.set("processing_" .. filepath, nil)
		end, 100)
	end

	-- Detect file type
	local ext = vim.fn.fnamemodify(filepath, ":e")
	local ft = vim.bo.filetype

	-- Show that detection is happening
	if notifications.get_config().debug_mode then
		notifications.notify(
			string.format("[Detector] Processing %s (ext: %s, ft: %s)", filepath, ext, ft),
			vim.log.levels.DEBUG
		)
	end

	-- Route to appropriate handler (Python only) with error protection
	local ok, err = pcall(function()
		if ext == "ipynb" then
			M.handle_notebook(filepath)
		elseif ext == "py" or ft == "python" then
			M.handle_python(filepath)
		end
	end)

	-- Always clear the processing flag, even if handler failed
	clear_processing_flag()

	-- Log error if handler failed (but don't propagate it)
	if not ok then
		notifications.notify(
			string.format("Error processing %s: %s", vim.fn.fnamemodify(filepath, ":t"), tostring(err)),
			vim.log.levels.ERROR
		)
	end
end

-- Handle notebook files
function M.handle_notebook(filepath)
	-- Step 1: Ensure jupytext is available
	local notebook = require("pyworks.notebook.jupytext")
	if not notebook.ensure_jupytext() then
		-- Get project info for better instructions
		local project_dir, venv_path = utils.get_project_paths(filepath)
		local project_type = utils.detect_project_type(project_dir)
		local project_rel = vim.fn.fnamemodify(project_dir, ":~:.")

		notifications.notify(
			string.format("❌ Cannot open %s notebook: jupytext not found", project_type),
			vim.log.levels.ERROR
		)
		notifications.notify(
			string.format("💡 Run :PyworksSetup to create venv at: %s/.venv", project_rel),
			vim.log.levels.INFO
		)
		return
	end

	-- Handle as Python notebook (pyworks only supports Python)
	M.handle_python_notebook(filepath)
end

-- Get available kernels dynamically (with timeout to prevent UI blocking)
local function get_available_kernels()
	local success, result, _ =
		utils.system_with_timeout("jupyter kernelspec list --json 2>/dev/null", KERNEL_LIST_TIMEOUT_MS)
	if not success then
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
		local project_dir, venv_path = utils.get_project_paths(filepath)

		-- Debug logging (only if debug mode)
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
						{ action_required = true }
					)
					-- Create venv if it doesn't have Python
					local python_module = require("pyworks.languages.python")
					python_module.create_venv(filepath)
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

		-- Find a kernel that uses this project's Python (with timeout)
		local kern_success, result, _ =
			utils.system_with_timeout("jupyter kernelspec list --json 2>/dev/null", KERNEL_LIST_TIMEOUT_MS)
		if kern_success then
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
								-- Found an exact match! (show once, deduplication handles repeats)
								notifications.notify(
									string.format("✅ Found kernel '%s'", name),
									vim.log.levels.INFO
								)
								return name
							elseif kernel_python:match("^" .. vim.pesc(venv_path)) then
								-- Kernel is from our exact venv directory
								notifications.notify(
									string.format("✅ Found kernel '%s'", name),
									vim.log.levels.INFO
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

		-- Check if ipykernel is installed before creating kernel (with safe escaping and timeout)
		local check_cmd = string.format(
			"%s -c %s 2>/dev/null",
			vim.fn.shellescape(python_path),
			vim.fn.shellescape("import ipykernel")
		)
		local check_success, _, _ = utils.system_with_timeout(check_cmd, KERNEL_LIST_TIMEOUT_MS)
		if not check_success then
			notifications.notify(
				string.format("❌ ipykernel not found in venv. Run: %s/bin/pip install ipykernel", venv_path),
				vim.log.levels.ERROR,
				{ action_required = true }
			)
			return nil
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

		local create_success, output, _ = utils.system_with_timeout(cmd, KERNEL_CREATE_TIMEOUT_MS)
		if create_success then
			notifications.notify(
				string.format("✅ Created kernel '%s' -> %s", kernel_name, python_path),
				vim.log.levels.INFO
			)
			-- Clear kernel cache to pick up the new kernel
			cached_kernels = nil
			return kernel_name
		else
			notifications.notify(
				string.format("❌ Failed to create kernel: %s", vim.trim(output)),
				vim.log.levels.ERROR
			)
			return nil
		end
	else
		-- Fallback: generic kernel lookup when no filepath provided
		-- Refresh cache if older than 60 seconds
		local now = vim.uv.now()
		if not cached_kernels or (now - kernel_cache_time) > 60000 then
			cached_kernels = get_available_kernels()
			kernel_cache_time = now
		end

		-- Look up kernel for this language
		local lang = language:lower()
		local kernel = cached_kernels[lang]
		if kernel then
			notifications.notify(string.format("🎯 Using %s kernel: %s", language, kernel), vim.log.levels.INFO)
		end
		return kernel
	end
end

-- Initialize Molten automatically for the language
local function auto_init_molten(language, filepath)
	-- Check if Molten is available
	if vim.fn.exists(":MoltenInit") ~= 2 then
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
	notifications.notify(string.format("Setting up %s kernel for execution...", language), vim.log.levels.INFO)

	-- Get the actual kernel name for this language and project
	local kernel = get_kernel_for_language(language, filepath)

	if kernel then
		-- Initialize Molten after a delay to ensure:
		-- 1. Buffer is fully loaded and ready
		-- 2. Any auto-commands have finished
		-- 3. LSP and other plugins have initialized
		-- Note: This is a pragmatic workaround. Ideally we'd use callbacks.
		vim.defer_fn(function()
			-- Try to initialize the kernel
			local ok, err = pcall(vim.cmd, "MoltenInit " .. kernel)
			if ok then
				vim.b[bufnr].molten_initialized = true

				-- Show clear notification that kernel is ready
				notifications.notify(
					string.format("✅ Molten ready with %s kernel - Use <leader>jl to run code", kernel),
					vim.log.levels.INFO
				)
			else
				-- If initialization failed, try again later or let user do it manually
				vim.b[bufnr].molten_init_attempted = false -- Allow retry
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
		-- No kernel found
		vim.b[bufnr].molten_init_attempted = false -- Allow retry
		notifications.notify("Python kernel not found. Run :PyworksSetup to configure.", vim.log.levels.WARN)
	end
end

-- Python file handler
function M.handle_python(filepath)
	-- Set up Python host for this file's project
	local python = require("pyworks.languages.python")
	python.setup_python_host(filepath)

	-- Show detailed project and venv detection
	local project_dir, venv_path = utils.get_project_paths(filepath)

	-- Get relative paths for cleaner display
	local file_rel = vim.fn.fnamemodify(filepath, ":~:.")
	local project_rel = vim.fn.fnamemodify(project_dir, ":~:.")
	local venv_exists = vim.fn.isdirectory(venv_path) == 1

	-- Detect project type
	local project_type = utils.detect_project_type(project_dir)

	-- Show detection results (deduplication handles repeats)
	if venv_exists then
		notifications.notify(
			string.format("🐍 %s project: venv at %s/.venv", project_type, project_rel),
			vim.log.levels.INFO
		)
	else
		notifications.notify(
			string.format("⚠️  %s project: No venv for %s", project_type, file_rel),
			vim.log.levels.WARN,
			{ action_required = true }
		)
		notifications.notify(
			string.format("💡 Run :PyworksSetup to create venv at: %s/.venv", project_rel),
			vim.log.levels.INFO
		)
		-- Don't auto-create on file open, but still set up for manual creation
		-- Store filepath for PyworksSetup command
		vim.b.pyworks_filepath = filepath
		return
	end

	python.handle_file(filepath, false) -- false = not a notebook
	auto_init_molten("python", filepath)
end

-- Python notebook handler
function M.handle_python_notebook(filepath)
	-- Set up Python host for this file's project
	local python = require("pyworks.languages.python")
	python.setup_python_host(filepath)

	-- Show detailed project and venv detection for notebooks
	local project_dir, venv_path = utils.get_project_paths(filepath)

	-- Get relative paths for cleaner display
	local file_rel = vim.fn.fnamemodify(filepath, ":~:.")
	local project_rel = vim.fn.fnamemodify(project_dir, ":~:.")
	local venv_exists = vim.fn.isdirectory(venv_path) == 1

	-- Detect project type
	local project_type = utils.detect_project_type(project_dir)

	-- Show detection results (first time only, not forced)
	if venv_exists then
		notifications.notify(
			string.format("📓 %s notebook: venv at %s/.venv", project_type, project_rel),
			vim.log.levels.INFO
		)
	else
		notifications.notify(
			string.format("⚠️  %s notebook: No venv for %s", project_type, file_rel),
			vim.log.levels.WARN,
			{ action_required = true }
		)
		notifications.notify(
			string.format("💡 Run :PyworksSetup to create venv at: %s/.venv", project_rel),
			vim.log.levels.INFO
		)
		-- Don't auto-create for notebooks, let user decide
		return
	end

	python.handle_file(filepath, true) -- true = is a notebook
	auto_init_molten("python", filepath)
end

-- Re-scan imports on file save
function M.rescan_imports(filepath)
	local ext = vim.fn.fnamemodify(filepath, ":e")
	local ft = vim.bo.filetype

	if ext == "ipynb" or ext == "py" or ft == "python" then
		local packages = require("pyworks.core.packages")
		packages.rescan_for_language(filepath, "python")
	end
end

-- Export kernel detection for use in other modules
M.get_kernel_for_language = get_kernel_for_language
-- Export for testing
M.detect_notebook_language = detect_notebook_language

return M
