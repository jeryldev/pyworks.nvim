-- pyworks.nvim - Zero-config multi-language support for Python, Julia, and R
-- Version: 3.0.0
--
-- Features:
-- - Automatic environment setup for Python, Julia, and R
-- - Smart package detection and installation
-- - Jupyter notebook support with automatic kernel management
-- - Zero configuration required - just open files and start working

local M = {}

-- Default configuration
local default_config = {
	python = {
		use_uv = false,
		preferred_venv_name = ".venv",
		auto_install_essentials = true,
		essentials = { "pynvim", "ipykernel", "jupyter_client", "jupytext" },
	},
	julia = {
		auto_install_ijulia = true,
	},
	r = {
		auto_install_irkernel = true,
	},
	cache = {
		-- Cache TTL overrides (in seconds)
		kernel_list = 60,
		installed_packages = 300,
	},
	notifications = {
		verbose_first_time = true,
		silent_when_ready = true,
		show_progress = true,
		debug_mode = false,
	},
	auto_detect = true, -- Automatically detect and setup on file open
}

-- Plugin configuration
local config = {}

-- Auto-configure external dependencies with proven settings
function M.configure_dependencies(opts)
	opts = opts or {}

	-- Configure Molten with optimal settings (only if molten is available)
	if not opts.skip_molten and vim.fn.exists(":MoltenInit") == 2 then
		vim.g.molten_image_provider = "image.nvim"
		vim.g.molten_auto_open_output = true
		vim.g.molten_virt_text_output = false -- Don't show inline virtual text
		vim.g.molten_virt_lines_off_by_1 = false
		vim.g.molten_output_win_max_height = 40
		vim.g.molten_output_win_max_width = 150
		vim.g.molten_output_crop_border = true
		vim.g.molten_wrap_output = true
		vim.g.molten_output_show_more = true
		vim.g.molten_output_win_border = "rounded"
		vim.g.molten_auto_open_html_in_browser = false
		vim.g.molten_auto_image_popup = false
		vim.g.molten_tick_rate = 100
	end

	-- Configure jupytext with PATH management and optimal settings
	if not opts.skip_jupytext then
		-- Add venv/bin to PATH for jupytext command
		local cwd = vim.fn.getcwd()
		local paths_to_add = {}

		-- Check current directory venv
		local venv_bin = cwd .. "/.venv/bin"
		if vim.fn.isdirectory(venv_bin) == 1 then
			table.insert(paths_to_add, venv_bin)
		end

		-- Check parent directory venv
		local parent_venv = vim.fn.fnamemodify(cwd, ":h") .. "/.venv/bin"
		if vim.fn.isdirectory(parent_venv) == 1 then
			table.insert(paths_to_add, parent_venv)
		end

		-- Check conda environment
		local conda_prefix = vim.env.CONDA_PREFIX
		if conda_prefix then
			local conda_bin = conda_prefix .. "/bin"
			if vim.fn.isdirectory(conda_bin) == 1 then
				table.insert(paths_to_add, conda_bin)
			end
		end

		-- Update PATH
		if #paths_to_add > 0 then
			vim.env.PATH = table.concat(paths_to_add, ":") .. ":" .. vim.env.PATH
		end

		-- Auto-configure jupytext if available
		local ok, jupytext = pcall(require, "jupytext")
		if ok then
			-- Find jupytext command
			local jupytext_cmd = "jupytext"
			local venv_jupytext = cwd .. "/.venv/bin/jupytext"
			if vim.fn.executable(venv_jupytext) == 1 then
				jupytext_cmd = venv_jupytext
			else
				local parent_jupytext = vim.fn.fnamemodify(cwd, ":h") .. "/.venv/bin/jupytext"
				if vim.fn.executable(parent_jupytext) == 1 then
					jupytext_cmd = parent_jupytext
				end
			end

			jupytext.setup({
				style = "percent",
				output_extension = "auto",
				force_ft = nil,
				jupytext_command = jupytext_cmd,
				custom_language_formatting = {
					python = { extension = "py", style = "percent", comment = "#" },
					julia = { extension = "jl", style = "percent", comment = "#" },
					r = { extension = "R", style = "percent", comment = "#" },
				},
			})
		end
	end

	-- Configure image.nvim with optimal settings
	if not opts.skip_image then
		local ok, image = pcall(require, "image")
		if ok then
			local backend = opts.image_backend or "kitty" -- Default to kitty
			image.setup({
				backend = backend,
				integrations = {
					markdown = {
						enabled = true,
						clear_in_insert_mode = false,
						download_remote_images = true,
						only_render_image_at_cursor = false,
						filetypes = { "markdown", "vimwiki" },
					},
					html = { enabled = false },
					css = { enabled = false },
				},
				max_width = 150,
				max_height = 40,
				max_height_window_percentage = math.huge,
				max_width_window_percentage = math.huge,
				window_overlap_clear_enabled = true,
				window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
				editor_only_render_when_focused = false,
				tmux_show_only_in_active_window = false,
			})
		end
	end
end

-- Setup function
function M.setup(opts)
	-- Prevent multiple setup calls
	if vim.g.pyworks_setup_complete then
		return
	end

	-- Auto-configure dependencies with proven settings
	-- Use defer_fn to ensure plugins are loaded
	vim.defer_fn(function()
		M.configure_dependencies(opts)
	end, 100)

	-- Add helpful keymaps
	if not opts.skip_keymaps then
		vim.keymap.set("n", "<leader>ps", "<cmd>PyworksStatus<cr>", { desc = "Pyworks: Show package status" })
		vim.keymap.set("n", "<leader>pc", "<cmd>PyworksClearCache<cr>", { desc = "Pyworks: Clear cache" })
	end

	-- Merge user configuration with defaults
	config = vim.tbl_deep_extend("force", default_config, opts or {})

	-- Configure core modules
	local cache = require("pyworks.core.cache")
	cache.configure(config.cache)

	local notifications = require("pyworks.core.notifications")
	notifications.configure(config.notifications)

	-- Configure language modules
	local python = require("pyworks.languages.python")
	python.configure(config.python)

	-- Initialize state
	local state = require("pyworks.core.state")
	state.start_session()

	-- Set Python host if not already set
	if not vim.g.python3_host_prog then
		M.setup_python_host()
	end

	-- Mark setup as complete
	vim.g.pyworks_setup_complete = true
end

-- Setup Python host
-- Now supports per-buffer configuration based on file location
function M.setup_python_host(filepath)
	local utils = require("pyworks.utils")
	local python_candidates = {}
	
	if filepath then
		-- Get project-specific venv
		local project_dir, venv_path = utils.get_project_paths(filepath)
		table.insert(python_candidates, venv_path .. "/bin/python3")
		table.insert(python_candidates, venv_path .. "/bin/python")
	else
		-- Fallback to cwd-based detection
		table.insert(python_candidates, vim.fn.getcwd() .. "/.venv/bin/python3")
		table.insert(python_candidates, vim.fn.getcwd() .. "/.venv/bin/python")
	end
	
	-- Add system Python as fallback
	table.insert(python_candidates, vim.fn.exepath("python3"))
	table.insert(python_candidates, vim.fn.exepath("python"))

	for _, python_path in ipairs(python_candidates) do
		if vim.fn.executable(python_path) == 1 then
			-- Set buffer-local Python if filepath provided
			if filepath then
				vim.b.python3_host_prog = python_path
				-- Also update global for compatibility
				vim.g.python3_host_prog = python_path
			else
				vim.g.python3_host_prog = python_path
			end
			break
		end
	end
end

-- Manual commands (for power users)
-- These are optional - the plugin works without them

-- Command to manually trigger environment setup
vim.api.nvim_create_user_command("PyworksSetup", function()
	local detector = require("pyworks.core.detector")
	local filepath = vim.api.nvim_buf_get_name(0)
	detector.on_file_open(filepath)
end, {
	desc = "Manually trigger Pyworks environment setup for current file",
})

-- Command to install missing packages
vim.api.nvim_create_user_command("PyworksInstall", function()
	local ft = vim.bo.filetype
	if ft == "python" then
		local python = require("pyworks.languages.python")
		python.install_missing_packages()
	elseif ft == "julia" then
		local julia = require("pyworks.languages.julia")
		julia.install_missing_packages()
	elseif ft == "r" then
		local r = require("pyworks.languages.r")
		r.install_missing_packages()
	else
		vim.notify("No missing packages detected for this file type", vim.log.levels.INFO)
	end
end, {
	desc = "Install missing packages for current file",
})

-- Command to show package status
vim.api.nvim_create_user_command("PyworksStatus", function()
	local packages = require("pyworks.core.packages")
	local ft = vim.bo.filetype
	local language = nil

	if ft == "python" then
		language = "python"
	elseif ft == "julia" then
		language = "julia"
	elseif ft == "r" then
		language = "r"
	end

	if language then
		local result = packages.analyze_buffer(language)

		vim.notify(
			string.format(
				"[%s] Imports: %d | Installed: %d | Missing: %d",
				language:gsub("^%l", string.upper),
				#result.imports,
				#result.installed,
				#result.missing
			),
			vim.log.levels.INFO
		)

		if #result.missing > 0 then
			vim.notify("Missing packages: " .. table.concat(result.missing, ", "), vim.log.levels.WARN)
		end
	else
		vim.notify("Pyworks: Not a supported file type", vim.log.levels.INFO)
	end
end, {
	desc = "Show package status for current file",
})

-- Command to clear cache
vim.api.nvim_create_user_command("PyworksClearCache", function()
	local cache = require("pyworks.core.cache")
	cache.clear()
	vim.notify("Pyworks cache cleared", vim.log.levels.INFO)
end, {
	desc = "Clear Pyworks cache",
})

-- Command to show cache statistics
vim.api.nvim_create_user_command("PyworksCacheStats", function()
	local cache = require("pyworks.core.cache")
	local stats = cache.stats()
	vim.notify(
		string.format("Cache: %d total | %d active | %d expired", stats.total, stats.active, stats.expired),
		vim.log.levels.INFO
	)
end, {
	desc = "Show Pyworks cache statistics",
})

-- Python-specific package management commands
vim.api.nvim_create_user_command("PyworksInstallPython", function(opts)
	local python = require("pyworks.languages.python")
	if opts.args and opts.args ~= "" then
		python.install_python_packages(opts.args)
	else
		vim.ui.input({ prompt = "Python packages to install (space/comma separated): " }, function(input)
			if input and input ~= "" then
				python.install_python_packages(input)
			end
		end)
	end
end, {
	nargs = "*",
	desc = "Install Python packages in project virtual environment",
	complete = function()
		-- Suggest common packages
		return { "numpy", "pandas", "matplotlib", "requests", "pytest", "black", "flake8", "mypy" }
	end,
})

vim.api.nvim_create_user_command("PyworksUninstallPython", function(opts)
	local python = require("pyworks.languages.python")
	if opts.args and opts.args ~= "" then
		python.uninstall_python_packages(opts.args)
	else
		vim.ui.input({ prompt = "Python packages to uninstall (space/comma separated): " }, function(input)
			if input and input ~= "" then
				python.uninstall_python_packages(input)
			end
		end)
	end
end, {
	nargs = "*",
	desc = "Uninstall Python packages from project virtual environment",
})

vim.api.nvim_create_user_command("PyworksListPython", function()
	local python = require("pyworks.languages.python")
	python.list_python_packages()
end, {
	desc = "List installed Python packages in project virtual environment",
})

-- Export configuration for other modules
function M.get_config()
	return config
end

-- Health check function
function M.health()
	local health = vim.health or require("health")

	health.start("Pyworks")

	-- Check Python
	local python = require("pyworks.languages.python")
	if python.has_venv() then
		health.ok("Python virtual environment found")
	else
		health.warn("No Python virtual environment found", {
			"Will be created automatically when you open a Python file",
		})
	end

	-- Check Julia
	local julia = require("pyworks.languages.julia")
	if julia.has_julia() then
		health.ok("Julia installation found")
		if julia.has_ijulia() then
			health.ok("IJulia kernel installed")
		else
			health.warn("IJulia kernel not installed", {
				"Will be prompted to install when you open a Julia notebook",
			})
		end
	else
		health.warn("Julia not found", {
			"Install Julia from https://julialang.org",
		})
	end

	-- Check R
	local r = require("pyworks.languages.r")
	if r.has_r() then
		health.ok("R installation found")
		if r.has_irkernel() then
			health.ok("IRkernel installed")
		else
			health.warn("IRkernel not installed", {
				"Will be prompted to install when you open an R notebook",
			})
		end
	else
		health.warn("R not found", {
			"Install R from https://www.r-project.org",
		})
	end

	-- Check jupytext
	local jupytext = require("pyworks.notebook.jupytext")
	if jupytext.is_jupytext_installed() then
		health.ok("Jupytext installed")
	else
		health.warn("Jupytext not installed", {
			"Will be prompted to install when you open a notebook",
		})
	end
end

return M

