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

local function get_kernel_for_language(language)
	-- Refresh cache if older than 60 seconds
	local now = vim.loop.now()
	if not cached_kernels or (now - kernel_cache_time) > 60000 then
		cached_kernels = get_available_kernels()
		kernel_cache_time = now
	end

	-- Look up kernel for this language
	local lang = language:lower()
	return cached_kernels[lang]
end

-- Initialize Molten automatically for the language
local function auto_init_molten(language)
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

	-- Get the actual kernel name for this language
	local kernel = get_kernel_for_language(language)

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
	
	local python = require("pyworks.languages.python")
	python.handle_file(filepath, false) -- false = not a notebook
	auto_init_molten("python")
end

-- Python notebook handler
function M.handle_python_notebook(filepath)
	-- Set up Python host for this file's project
	local init = require("pyworks.init")
	init.setup_python_host(filepath)
	
	local python = require("pyworks.languages.python")
	python.handle_file(filepath, true) -- true = is a notebook
	auto_init_molten("python")
end

-- Julia file handler
function M.handle_julia(filepath)
	local julia = require("pyworks.languages.julia")
	julia.handle_file(filepath, false)
	auto_init_molten("julia")
end

-- Julia notebook handler
function M.handle_julia_notebook(filepath)
	local julia = require("pyworks.languages.julia")
	julia.handle_file(filepath, true)
	auto_init_molten("julia")
end

-- R file handler
function M.handle_r(filepath)
	local r = require("pyworks.languages.r")
	r.handle_file(filepath, false)
	auto_init_molten("r")
end

-- R notebook handler
function M.handle_r_notebook(filepath)
	local r = require("pyworks.languages.r")
	r.handle_file(filepath, true)
	auto_init_molten("r")
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

