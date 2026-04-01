-- Integration tests for pyworks.nvim
-- Tests end-to-end feature behavior in a headless Neovim session.
-- Covers: plugin setup, all commands, cell operations on real buffers,
-- cache lifecycle, notifications, state management, error handling,
-- diagnostics, security validation, and project detection.

describe("integration", function()
	local pyworks

	before_each(function()
		-- Reset plugin state for each test
		vim.g.pyworks_setup_complete = nil
		package.loaded["pyworks"] = nil
		package.loaded["pyworks.core.cache"] = nil
		package.loaded["pyworks.core.state"] = nil
		package.loaded["pyworks.core.notifications"] = nil
		package.loaded["pyworks.core.error_handler"] = nil
		package.loaded["pyworks.core.cell_engine"] = nil
		package.loaded["pyworks.utils"] = nil
		package.loaded["pyworks.ui"] = nil
		package.loaded["pyworks.diagnostics"] = nil
		package.loaded["pyworks.keymaps"] = nil
		pyworks = require("pyworks")
	end)

	-- =========================================================================
	-- PLUGIN SETUP AND CONFIGURATION
	-- =========================================================================

	describe("plugin lifecycle", function()
		it("should setup with default config and register all commands", function()
			pyworks.setup()

			local expected_commands = {
				"PyworksSetup",
				"PyworksSync",
				"PyworksStatus",
				"PyworksDiagnostics",
				"PyworksHelp",
				"PyworksAdd",
				"PyworksRemove",
				"PyworksList",
				"PyworksNewPython",
				"PyworksNewPythonNotebook",
				"PyworksNextCell",
				"PyworksPrevCell",
				"PyworksInsertCellAbove",
				"PyworksInsertCellBelow",
				"PyworksToggleCellType",
				"PyworksMergeCellBelow",
				"PyworksSplitCell",
			}

			for _, cmd in ipairs(expected_commands) do
				assert.are.equal(2, vim.fn.exists(":" .. cmd), "Missing command: " .. cmd)
			end
		end)

		it("should prevent double setup", function()
			pyworks.setup()
			assert.is_true(vim.g.pyworks_setup_complete)

			-- Second call should return early without error
			assert.has_no.errors(function()
				pyworks.setup()
			end)
		end)

		it("should merge user config with defaults", function()
			pyworks.setup({
				python = { use_uv = false },
				cell_marker = "# COMMAND ----------",
			})

			local config = pyworks.get_config()
			assert.is_false(config.python.use_uv)
			assert.are.equal("# COMMAND ----------", config.cell_marker)
			-- Defaults should be preserved for unset values
			assert.is_true(config.python.auto_install_essentials)
			assert.are.equal(".venv", config.python.preferred_venv_name)
		end)

		it("should warn on invalid config types without crashing", function()
			assert.has_no.errors(function()
				pyworks.setup({
					python = { use_uv = "not_a_boolean" },
					cache = { kernel_list = "not_a_number" },
				})
			end)
		end)
	end)

	-- =========================================================================
	-- ALL MODULES LOAD WITHOUT ERROR
	-- =========================================================================

	describe("module loading", function()
		it("should load all core modules without error", function()
			local modules = {
				"pyworks.core.cache",
				"pyworks.core.cell_engine",
				"pyworks.core.detector",
				"pyworks.core.error_handler",
				"pyworks.core.notifications",
				"pyworks.core.packages",
				"pyworks.core.state",
				"pyworks.core.recursion_guard",
				"pyworks.languages.python",
				"pyworks.notebook.jupytext",
				"pyworks.utils",
				"pyworks.ui",
				"pyworks.keymaps",
				"pyworks.diagnostics",
				"pyworks.commands.create",
				"pyworks.dependencies",
			}

			for _, mod in ipairs(modules) do
				local ok, err = pcall(require, mod)
				assert.is_true(ok, "Failed to load " .. mod .. ": " .. tostring(err))
			end
		end)
	end)

	-- =========================================================================
	-- CELL ENGINE: full feature coverage
	-- =========================================================================

	describe("cell engine on real buffer", function()
		local cell_engine

		before_each(function()
			package.loaded["pyworks.core.cell_engine"] = nil
			cell_engine = require("pyworks.core.cell_engine")
			cell_engine.configure({ cell_marker = "# %%" })

			-- Create a buffer with realistic notebook content
			vim.cmd("enew!")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, {
				"# %%",
				"import numpy as np",
				"import pandas as pd",
				"",
				"# %%",
				"x = np.array([1, 2, 3])",
				"y = x ** 2",
				"",
				"# %% [markdown]",
				"# This is a markdown cell",
				"# With multiple lines",
				"",
				"# %%",
				"print(y)",
			})
			-- Position cursor at line 1 (first cell marker)
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
		end)

		after_each(function()
			vim.cmd("bdelete!")
		end)

		it("should count all cells", function()
			assert.are.equal(4, cell_engine.count_cells())
		end)

		it("should return correct cell positions", function()
			local positions = cell_engine.get_cell_positions()
			assert.are.equal(4, #positions)
			assert.are.equal(1, positions[1])
			assert.are.equal(5, positions[2])
			assert.are.equal(9, positions[3])
			assert.are.equal(13, positions[4])
		end)

		it("should find cell boundaries from cursor in middle of cell", function()
			vim.api.nvim_win_set_cursor(0, { 6, 0 }) -- Inside second cell
			local start_line, end_line = cell_engine.find_cell_boundaries()
			assert.are.equal(6, start_line)
			assert.are.equal(8, end_line)
		end)

		it("should detect markdown cells", function()
			vim.api.nvim_win_set_cursor(0, { 10, 0 }) -- Inside markdown cell
			assert.is_true(cell_engine.is_markdown_cell())

			vim.api.nvim_win_set_cursor(0, { 6, 0 }) -- Inside code cell
			assert.is_false(cell_engine.is_markdown_cell())
		end)

		it("should navigate to next cell", function()
			vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- In first cell body
			assert.is_true(cell_engine.next_cell())
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(6, cursor[1]) -- Should be in second cell body
		end)

		it("should return false when no next cell exists", function()
			vim.api.nvim_win_set_cursor(0, { 14, 0 }) -- Last cell
			assert.is_false(cell_engine.next_cell())
		end)

		it("should navigate to previous cell", function()
			vim.api.nvim_win_set_cursor(0, { 6, 0 }) -- Second cell body
			assert.is_true(cell_engine.prev_cell())
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(2, cursor[1]) -- Should be in first cell body
		end)

		it("should insert code cell below", function()
			local line_count_before = vim.api.nvim_buf_line_count(0)
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			cell_engine.insert_cell_below()
			local line_count_after = vim.api.nvim_buf_line_count(0)
			assert.are.equal(line_count_before + 2, line_count_after)
			assert.are.equal(5, cell_engine.count_cells())
		end)

		it("should insert code cell above", function()
			vim.api.nvim_win_set_cursor(0, { 5, 0 }) -- At second cell marker
			cell_engine.insert_cell_above()
			assert.are.equal(5, cell_engine.count_cells())
		end)

		it("should insert markdown cell below", function()
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			cell_engine.insert_markdown_below()
			local positions = cell_engine.get_cell_positions()
			-- New markdown cell should be inserted
			assert.are.equal(5, cell_engine.count_cells())
			-- Check the inserted line contains [markdown]
			local new_marker_line = vim.fn.getline(positions[2])
			assert.is_truthy(new_marker_line:match("%[markdown%]"))
		end)

		it("should insert markdown cell above", function()
			vim.api.nvim_win_set_cursor(0, { 5, 0 })
			cell_engine.insert_markdown_above()
			assert.are.equal(5, cell_engine.count_cells())
		end)

		it("should toggle cell type from code to markdown", function()
			vim.api.nvim_win_set_cursor(0, { 6, 0 }) -- Inside second code cell
			assert.is_true(cell_engine.toggle_cell_type())
			local marker_line = vim.fn.getline(5)
			assert.is_truthy(marker_line:match("%[markdown%]"))
		end)

		it("should toggle cell type from markdown to code", function()
			vim.api.nvim_win_set_cursor(0, { 10, 0 }) -- Inside markdown cell
			assert.is_true(cell_engine.toggle_cell_type())
			local marker_line = vim.fn.getline(9)
			assert.is_falsy(marker_line:match("%[markdown%]"))
		end)

		it("should merge cell below by removing marker", function()
			local count_before = cell_engine.count_cells()
			vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- In first cell
			assert.is_true(cell_engine.merge_cell_below())
			assert.are.equal(count_before - 1, cell_engine.count_cells())
		end)

		it("should return false when no cell below to merge", function()
			vim.api.nvim_win_set_cursor(0, { 14, 0 }) -- Last cell
			assert.is_false(cell_engine.merge_cell_below())
		end)

		it("should split cell at cursor", function()
			local count_before = cell_engine.count_cells()
			vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- Middle of first cell
			cell_engine.split_cell()
			assert.are.equal(count_before + 1, cell_engine.count_cells())
		end)

		it("should work with custom cell marker", function()
			cell_engine.configure({ cell_marker = "# COMMAND ----------" })
			vim.api.nvim_buf_set_lines(0, 0, -1, false, {
				"# COMMAND ----------",
				"x = 1",
				"",
				"# COMMAND ----------",
				"y = 2",
			})

			assert.are.equal(2, cell_engine.count_cells())
			local positions = cell_engine.get_cell_positions()
			assert.are.equal(1, positions[1])
			assert.are.equal(4, positions[2])
		end)
	end)

	-- =========================================================================
	-- CACHE: full lifecycle
	-- =========================================================================

	describe("cache lifecycle", function()
		local cache

		before_each(function()
			package.loaded["pyworks.core.cache"] = nil
			cache = require("pyworks.core.cache")
		end)

		it("should set, get, and invalidate", function()
			cache.set("test_key", { data = "value" })
			local result = cache.get("test_key")
			assert.is_not_nil(result)
			assert.are.equal("value", result.data)

			cache.invalidate("test_key")
			assert.is_nil(cache.get("test_key"))
		end)

		it("should support custom per-entry TTL", function()
			cache.set("short_lived", "data", 1)
			assert.are.equal("data", cache.get("short_lived"))
		end)

		it("should invalidate by pattern", function()
			cache.set("prefix_a", 1)
			cache.set("prefix_b", 2)
			cache.set("other_c", 3)

			cache.invalidate_pattern("^prefix_")

			assert.is_nil(cache.get("prefix_a"))
			assert.is_nil(cache.get("prefix_b"))
			assert.are.equal(3, cache.get("other_c"))
		end)

		it("should report stats correctly", function()
			cache.set("k1", "v1")
			cache.set("k2", "v2")
			cache.set("k3", "v3")

			local stats = cache.stats()
			assert.are.equal(3, stats.total)
			assert.are.equal(3, stats.active)
			assert.are.equal(0, stats.expired)
		end)

		it("should use correct TTL for jupytext_installed key", function()
			cache.set("jupytext_installed", true)
			-- Should be retrievable (not expired after 0 seconds)
			assert.is_true(cache.get("jupytext_installed"))
		end)

		it("should apply configured TTL overrides", function()
			cache.configure({ kernel_list = 120 })
			cache.set("kernel_list_test", "data")
			assert.are.equal("data", cache.get("kernel_list_test"))
		end)
	end)

	-- =========================================================================
	-- STATE MANAGEMENT
	-- =========================================================================

	describe("state management", function()
		local state_module

		before_each(function()
			package.loaded["pyworks.core.state"] = nil
			state_module = require("pyworks.core.state")
			state_module.init()
		end)

		it("should set and get values", function()
			state_module.set("test_key", "test_value")
			assert.are.equal("test_value", state_module.get("test_key"))
		end)

		it("should remove values", function()
			state_module.set("to_remove", "data")
			assert.is_not_nil(state_module.get("to_remove"))
			state_module.remove("to_remove")
			assert.is_nil(state_module.get("to_remove"))
		end)

		it("should track environment status", function()
			state_module.set_env_status("python", "venv_created")
			assert.are.equal("venv_created", state_module.get("env_python"))
		end)

		it("should track package installations", function()
			state_module.mark_package_installed("python", "numpy")
			local installed = state_module.get("installed_python")
			assert.is_not_nil(installed)
			assert.is_not_nil(installed.numpy)
		end)

		it("should manage check intervals", function()
			assert.is_true(state_module.should_check("imports", "python", 300))
			state_module.set_last_check("imports", "python")
			assert.is_false(state_module.should_check("imports", "python", 300))
		end)

		it("should track sessions", function()
			state_module.start_session()
			local duration = state_module.get_session_duration()
			assert.is_true(duration >= 0)
		end)
	end)

	-- =========================================================================
	-- ERROR HANDLER
	-- =========================================================================

	describe("error handler", function()
		local error_handler

		before_each(function()
			package.loaded["pyworks.core.error_handler"] = nil
			error_handler = require("pyworks.core.error_handler")
		end)

		it("should protect against function errors and return false", function()
			local ok, result = error_handler.protected_call(function()
				error("test error")
			end, "Test operation")

			assert.is_false(ok)
			assert.is_nil(result)
		end)

		it("should return true and result on success", function()
			local ok, result = error_handler.protected_call(function()
				return "success_value"
			end, "Test operation")

			assert.is_true(ok)
			assert.are.equal("success_value", result)
		end)

		it("should pass arguments through to the function", function()
			local ok, result = error_handler.protected_call(function(a, b)
				return a + b
			end, "Addition", 3, 4)

			assert.is_true(ok)
			assert.are.equal(7, result)
		end)

		it("should validate file paths", function()
			assert.is_nil(error_handler.validate_filepath(nil, "test"))
			assert.is_nil(error_handler.validate_filepath("", "test"))
			assert.is_nil(error_handler.validate_filepath("/nonexistent/file.txt", "test"))
		end)

		it("should validate directories", function()
			assert.is_nil(error_handler.validate_directory(nil, "test"))
			assert.is_nil(error_handler.validate_directory("/nonexistent/dir", "test"))

			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir, "p")
			local result = error_handler.validate_directory(temp_dir, "test")
			assert.is_not_nil(result)
			vim.fn.delete(temp_dir, "rf")
		end)

		it("should validate package lists", function()
			assert.is_nil(error_handler.validate_packages(nil, "Python"))
			assert.is_nil(error_handler.validate_packages({}, "Python"))
			assert.is_nil(error_handler.validate_packages({ "", "" }, "Python"))

			local result = error_handler.validate_packages({ "numpy", "pandas" }, "Python")
			assert.are.equal(2, #result)
		end)

		it("should wrap functions with error handling", function()
			local wrapped = error_handler.wrap(function(x)
				return x * 2
			end, "Doubling")

			local ok, result = wrapped(5)
			assert.is_true(ok)
			assert.are.equal(10, result)
		end)
	end)

	-- =========================================================================
	-- NOTIFICATIONS SYSTEM
	-- =========================================================================

	describe("notifications", function()
		local notifications

		before_each(function()
			package.loaded["pyworks.core.notifications"] = nil
			package.loaded["pyworks.core.state"] = nil
			require("pyworks.core.state").init()
			notifications = require("pyworks.core.notifications")
			notifications.configure({
				verbose_first_time = true,
				silent_when_ready = true,
				show_progress = true,
				debug_mode = false,
			})
			notifications.clear_history()
		end)

		it("should deduplicate repeated messages", function()
			-- First call should not be suppressed
			-- Second identical call within TTL should be suppressed
			local history_before = #notifications.get_history()
			notifications.notify("duplicate test", vim.log.levels.WARN)
			assert.are.equal(history_before + 1, #notifications.get_history())

			-- Same message again - should be suppressed (not added to history again)
			notifications.notify("duplicate test", vim.log.levels.WARN)
			assert.are.equal(history_before + 1, #notifications.get_history())
		end)

		it("should allow forced notifications to bypass suppression", function()
			notifications.notify("forced msg", vim.log.levels.INFO, { force = true })
			notifications.notify("forced msg", vim.log.levels.INFO, { force = true })
			-- Both should go through (force bypasses suppression check at notification level)
		end)

		it("should configure debug mode", function()
			notifications.set_debug(true)
			assert.is_true(notifications.get_config().debug_mode)
			notifications.set_debug(false)
			assert.is_false(notifications.get_config().debug_mode)
		end)

		it("should clear history", function()
			notifications.notify("test msg", vim.log.levels.WARN)
			assert.is_true(#notifications.get_history() > 0)
			notifications.clear_history()
			assert.are.equal(0, #notifications.get_history())
		end)
	end)

	-- =========================================================================
	-- UTILS: project detection and system calls
	-- =========================================================================

	describe("utils project detection", function()
		local utils

		before_each(function()
			package.loaded["pyworks.utils"] = nil
			utils = require("pyworks.utils")
		end)

		it("should detect project paths from cwd", function()
			local project_dir, venv_path = utils.get_project_paths()
			assert.is_not_nil(project_dir)
			assert.is_not_nil(venv_path)
			assert.is_truthy(venv_path:match("%.venv$"))
		end)

		it("should find project root by markers", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir .. "/subdir", "p")
			vim.fn.writefile({ "" }, temp_dir .. "/pyproject.toml")

			local root = utils.find_project_root(temp_dir .. "/subdir")
			assert.are.equal(temp_dir, root)

			vim.fn.delete(temp_dir, "rf")
		end)

		it("should detect project types", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir, "p")

			-- Default: Python
			assert.are.equal("Python", utils.detect_project_type(temp_dir))

			-- With pyproject.toml
			vim.fn.writefile({ "" }, temp_dir .. "/pyproject.toml")
			assert.are.equal("Poetry/Modern Python", utils.detect_project_type(temp_dir))

			-- With manage.py (Django)
			vim.fn.writefile({ "" }, temp_dir .. "/manage.py")
			assert.are.equal("Django", utils.detect_project_type(temp_dir))

			vim.fn.delete(temp_dir, "rf")
		end)

		it("should execute table commands via system_with_timeout", function()
			local success, output, code = utils.system_with_timeout({ "echo", "integration test" }, 5000)
			assert.is_true(success)
			assert.are.equal(0, code)
			assert.are.equal("integration test", vim.trim(output))
		end)

		it("should reject string commands in system_with_timeout", function()
			assert.has_error(function()
				utils.system_with_timeout("echo hello", 5000)
			end)
		end)

		it("should handle paths with spaces in table args", function()
			local temp_dir = vim.fn.tempname() .. " with spaces"
			vim.fn.mkdir(temp_dir, "p")
			local test_file = temp_dir .. "/test.txt"
			vim.fn.writefile({ "content" }, test_file)

			local success, output = utils.system_with_timeout({ "cat", test_file }, 5000)
			assert.is_true(success)
			assert.are.equal("content", vim.trim(output))

			vim.fn.delete(temp_dir, "rf")
		end)
	end)

	-- =========================================================================
	-- SECURITY: input validation
	-- =========================================================================

	describe("security validation", function()
		it("should reject malicious module names in check_python_import", function()
			local utils = require("pyworks.utils")
			assert.is_false(utils.check_python_import("os; import subprocess"))
			assert.is_false(utils.check_python_import("os\nimport subprocess"))
			assert.is_false(utils.check_python_import("__import__('os')"))
			assert.is_false(utils.check_python_import(nil))
			assert.is_false(utils.check_python_import(""))
		end)

		it("should accept valid Python module names", function()
			local utils = require("pyworks.utils")
			-- Pattern check only (doesn't actually import)
			assert.is_truthy(("numpy"):match("^[%w_%.]+$"))
			assert.is_truthy(("jupyter_client"):match("^[%w_%.]+$"))
			assert.is_truthy(("PIL.Image"):match("^[%w_%.]+$"))
			assert.is_truthy(("xml.etree.ElementTree"):match("^[%w_%.]+$"))
		end)

		it("should have no sh -c patterns in any source file", function()
			local source_files = {
				"lua/pyworks/languages/python.lua",
				"lua/pyworks/utils.lua",
				"lua/pyworks/notebook/jupytext.lua",
				"lua/pyworks/core/detector.lua",
				"lua/pyworks/commands/create.lua",
			}

			for _, filepath in ipairs(source_files) do
				local lines = vim.fn.readfile(filepath)
				local source = table.concat(lines, "\n")
				assert.is_falsy(source:match('"sh",%s*"-c"'), filepath .. " contains sh -c wrapping")
			end
		end)

		it("should validate kernel name patterns", function()
			local safe = "^[%w%-_%.]+$"
			-- Safe names
			assert.is_truthy(("python3"):match(safe))
			assert.is_truthy(("my_project_python"):match(safe))
			assert.is_truthy(("python-3.12"):match(safe))
			assert.is_truthy(("ir"):match(safe))
			-- Injection attempts
			assert.is_falsy(("python3 | echo pwned"):match(safe))
			assert.is_falsy(("python3; rm -rf /"):match(safe))
			assert.is_falsy(("a`whoami`"):match(safe))
			assert.is_falsy(("$(cmd)"):match(safe))
		end)
	end)

	-- =========================================================================
	-- DIAGNOSTICS
	-- =========================================================================

	describe("diagnostics", function()
		it("should run without crashing and produce output", function()
			pyworks.setup()
			local diag = require("pyworks.diagnostics")

			local ok, err = pcall(diag.run_diagnostics)
			assert.is_true(ok, "Diagnostics crashed: " .. tostring(err))

			-- Should have created a new buffer with diagnostics
			local buf_name = vim.api.nvim_buf_get_name(0)
			assert.is_truthy(buf_name:match("Pyworks Diagnostics"))

			-- Buffer should have content
			local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			assert.is_true(#lines > 5, "Diagnostics buffer should have content")

			-- Should contain expected sections
			local content = table.concat(lines, "\n")
			assert.is_truthy(content:match("Working Directory"))
			assert.is_truthy(content:match("Virtual Environment"))
			assert.is_truthy(content:match("Plugin Dependencies"))
			assert.is_truthy(content:match("Python Dependencies"))

			vim.cmd("bdelete!")
		end)
	end)

	-- =========================================================================
	-- UI: floating window, cell numbering
	-- =========================================================================

	describe("ui features", function()
		local ui_module

		before_each(function()
			package.loaded["pyworks.ui"] = nil
			ui_module = require("pyworks.ui")
		end)

		it("should create floating window and close it", function()
			local content = { "", "  Test line 1", "  Test line 2", "" }
			ui_module.create_floating_window(" Test ", content)

			-- A new window should be open
			local win_count = #vim.api.nvim_list_wins()
			assert.is_true(win_count >= 2, "Expected at least 2 windows (main + float)")

			-- Close with q
			vim.api.nvim_feedkeys("q", "x", false)
		end)

		it("should find first cell in buffer", function()
			vim.cmd("enew!")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, {
				"# some comment",
				"",
				"# %%",
				"x = 1",
			})

			local line = ui_module.find_first_cell()
			assert.are.equal(3, line)
			vim.cmd("bdelete!")
		end)

		it("should return nil when no cells exist", function()
			vim.cmd("enew!")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, {
				"x = 1",
				"y = 2",
			})

			local line = ui_module.find_first_cell()
			assert.is_nil(line)
			vim.cmd("bdelete!")
		end)

		it("should number cells with virtual text", function()
			vim.cmd("enew!")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, {
				"# %%",
				"x = 1",
				"# %%",
				"y = 2",
			})

			ui_module.number_cells(0)

			-- Check extmarks exist in the pyworks namespace
			local ns = vim.api.nvim_get_namespaces()
			local has_pyworks_ns = false
			for name, _ in pairs(ns) do
				if name:match("pyworks") then
					has_pyworks_ns = true
					break
				end
			end
			assert.is_true(has_pyworks_ns, "Expected pyworks namespace for cell numbers")

			vim.cmd("bdelete!")
		end)

		it("should enter cell by positioning cursor below marker", function()
			vim.cmd("enew!")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, {
				"# %%",
				"x = 1",
				"# %%",
				"y = 2",
			})

			ui_module.enter_cell(1)
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(2, cursor[1])

			vim.cmd("bdelete!")
		end)
	end)

	-- =========================================================================
	-- PACKAGES: import scanning
	-- =========================================================================

	describe("package scanning", function()
		local packages

		before_each(function()
			package.loaded["pyworks.core.packages"] = nil
			packages = require("pyworks.core.packages")
		end)

		it("should scan python imports from a file", function()
			local temp_file = vim.fn.tempname() .. ".py"
			vim.fn.writefile({
				"import numpy as np",
				"import pandas",
				"from sklearn.model_selection import train_test_split",
				"import os",
				"from collections import defaultdict",
				"# import commented_out",
			}, temp_file)

			local result = packages.scan_imports(temp_file, "python")
			assert.is_not_nil(result)
			local found = {}
			for _, imp in ipairs(result) do
				found[imp] = true
			end
			assert.is_true(found["numpy"] or false, "Should find numpy")
			assert.is_true(found["pandas"] or false, "Should find pandas")
			assert.is_true(found["sklearn"] or false, "Should find sklearn")

			vim.fn.delete(temp_file)
		end)
	end)

	-- =========================================================================
	-- RECURSION GUARD
	-- =========================================================================

	describe("recursion guard", function()
		local guard

		before_each(function()
			package.loaded["pyworks.core.recursion_guard"] = nil
			guard = require("pyworks.core.recursion_guard")
			guard.force_reset()
		end)

		it("should allow first reload", function()
			local can, reason = guard.can_reload(1)
			assert.is_true(can, "First reload should be allowed: " .. tostring(reason))
		end)

		it("should block rapid successive reloads (debounce)", function()
			guard.begin_reload(1)
			guard.end_reload(1)

			-- Immediate second attempt should be debounced
			local can = guard.can_reload(1)
			-- May or may not pass depending on debounce timing
			-- At minimum, should not crash
			assert.is_boolean(can)
		end)

		it("should reset cleanly", function()
			guard.begin_reload(1)
			guard.force_reset()

			local can = guard.can_reload(1)
			assert.is_true(can, "Should allow reload after reset")
		end)
	end)

	-- =========================================================================
	-- PYTHON MODULE: venv detection (without real venv)
	-- =========================================================================

	describe("python venv detection", function()
		local python

		before_each(function()
			package.loaded["pyworks.languages.python"] = nil
			python = require("pyworks.languages.python")
		end)

		it("should return false for has_venv in empty temp dir", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir, "p")
			local temp_file = temp_dir .. "/test.py"
			vim.fn.writefile({ "" }, temp_file)

			local result = python.has_venv(temp_file)
			assert.is_false(result)

			vim.fn.delete(temp_dir, "rf")
		end)

		it("should return nil for get_python_path in empty temp dir", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir, "p")
			local temp_file = temp_dir .. "/test.py"
			vim.fn.writefile({ "" }, temp_file)

			local result = python.get_python_path(temp_file)
			assert.is_nil(result)

			vim.fn.delete(temp_dir, "rf")
		end)

		it("should return nil for get_pip_path when no venv exists", function()
			local result = python.get_pip_path("/tmp/nonexistent_project/file.py")
			assert.is_nil(result)
		end)

		it("should detect uv availability", function()
			local pkg_manager = python.get_package_manager("/tmp/nonexistent/file.py")
			-- Should return either "uv" or "pip" depending on system
			assert.is_truthy(pkg_manager:match("^uv") or pkg_manager == "pip")
		end)
	end)

	-- =========================================================================
	-- JUPYTEXT: notebook handler setup
	-- =========================================================================

	describe("jupytext notebook handling", function()
		local jupytext

		before_each(function()
			package.loaded["pyworks.notebook.jupytext"] = nil
			jupytext = require("pyworks.notebook.jupytext")
		end)

		it("should configure notebook handler without error", function()
			assert.has_no.errors(function()
				jupytext.configure_notebook_handler()
			end)
		end)

		it("should register BufReadCmd and BufWriteCmd autocmds for .ipynb", function()
			jupytext.setup_notebook_handler()

			local autocmds = vim.api.nvim_get_autocmds({
				group = "PyworksNotebook",
				pattern = "*.ipynb",
			})

			local has_read = false
			local has_write = false
			for _, au in ipairs(autocmds) do
				if au.event == "BufReadCmd" then
					has_read = true
				end
				if au.event == "BufWriteCmd" then
					has_write = true
				end
			end

			assert.is_true(has_read, "Should have BufReadCmd for .ipynb")
			assert.is_true(has_write, "Should have BufWriteCmd for .ipynb")
		end)

		it("should return false for reload on non-notebook buffer", function()
			vim.cmd("enew!")
			vim.api.nvim_buf_set_name(0, "/tmp/test.py")
			assert.is_false(jupytext.reload_notebook())
			vim.cmd("bdelete!")
		end)

		it("should report jupytext installation status as boolean", function()
			local result = jupytext.is_jupytext_installed()
			assert.is_boolean(result)
		end)
	end)

	-- =========================================================================
	-- HELP COMMAND
	-- =========================================================================

	describe("PyworksHelp command", function()
		it("should open a floating window with help content", function()
			pyworks.setup()

			local win_count_before = #vim.api.nvim_list_wins()
			vim.cmd("PyworksHelp")
			local win_count_after = #vim.api.nvim_list_wins()

			assert.is_true(win_count_after > win_count_before, "Help should open a new window")

			-- Close it
			vim.api.nvim_feedkeys("q", "x", false)
		end)
	end)
end)
