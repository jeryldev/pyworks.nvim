-- Test suite for pyworks init module
-- Tests setup function and command registration

describe("pyworks", function()
	-- Reset state before each test
	before_each(function()
		-- Clear setup flag to allow re-running setup
		vim.g.pyworks_setup_complete = nil
		-- Clear any cached modules
		package.loaded["pyworks"] = nil
		package.loaded["pyworks.init"] = nil
	end)

	describe("setup", function()
		it("should not error when called without arguments", function()
			local pyworks = require("pyworks")

			-- This should NOT throw an error
			local ok, err = pcall(function()
				pyworks.setup()
			end)

			assert.is_true(ok, "setup() without arguments should not error: " .. tostring(err))
		end)

		it("should not error when called with empty table", function()
			local pyworks = require("pyworks")

			local ok, err = pcall(function()
				pyworks.setup({})
			end)

			assert.is_true(ok, "setup({}) should not error: " .. tostring(err))
		end)

		it("should not error when called with nil", function()
			local pyworks = require("pyworks")

			local ok, err = pcall(function()
				pyworks.setup(nil)
			end)

			assert.is_true(ok, "setup(nil) should not error: " .. tostring(err))
		end)

		it("should accept partial configuration", function()
			local pyworks = require("pyworks")

			local ok, err = pcall(function()
				pyworks.setup({
					python = {
						use_uv = false,
					},
				})
			end)

			assert.is_true(ok, "setup() with partial config should not error: " .. tostring(err))
		end)

		it("should set pyworks_setup_complete flag", function()
			local pyworks = require("pyworks")

			pyworks.setup()

			assert.is_true(vim.g.pyworks_setup_complete, "setup() should set pyworks_setup_complete flag")
		end)

		it("should not run twice when called multiple times", function()
			local pyworks = require("pyworks")

			-- First setup should complete
			pyworks.setup()
			assert.is_true(vim.g.pyworks_setup_complete, "first setup should complete")

			-- Second setup should be a no-op (guard check)
			local ok, err = pcall(function()
				pyworks.setup()
				pyworks.setup()
			end)

			assert.is_true(ok, "subsequent setup() calls should not error: " .. tostring(err))
			assert.is_true(vim.g.pyworks_setup_complete, "flag should remain set")
		end)
	end)

	describe("commands", function()
		it("should register PyworksNewPython command after setup", function()
			local pyworks = require("pyworks")
			pyworks.setup()

			-- Check if command exists
			local exists = vim.fn.exists(":PyworksNewPython") == 2

			assert.is_true(exists, "PyworksNewPython command should be registered")
		end)

		it("should register PyworksNewPythonNotebook command after setup", function()
			local pyworks = require("pyworks")
			pyworks.setup()

			-- Check if command exists
			local exists = vim.fn.exists(":PyworksNewPythonNotebook") == 2

			assert.is_true(exists, "PyworksNewPythonNotebook command should be registered")
		end)

		it("should register PyworksSetup command after setup", function()
			local pyworks = require("pyworks")
			pyworks.setup()

			local exists = vim.fn.exists(":PyworksSetup") == 2

			assert.is_true(exists, "PyworksSetup command should be registered")
		end)

		it("should register PyworksHelp command after setup", function()
			local pyworks = require("pyworks")
			pyworks.setup()

			local exists = vim.fn.exists(":PyworksHelp") == 2

			assert.is_true(exists, "PyworksHelp command should be registered")
		end)

		it("should register PyworksDiagnostics command", function()
			require("pyworks")
			local exists = vim.fn.exists(":PyworksDiagnostics") == 2

			assert.is_true(exists, "PyworksDiagnostics command should be registered")
		end)
	end)

	describe("get_config", function()
		it("should return configuration after setup", function()
			local pyworks = require("pyworks")
			pyworks.setup()

			local config = pyworks.get_config()

			assert.is_table(config, "get_config() should return a table")
			assert.is_table(config.python, "config should have python section")
			assert.is_table(config.notifications, "config should have notifications section")
		end)

		it("should merge user config with defaults", function()
			local pyworks = require("pyworks")
			pyworks.setup({
				python = {
					use_uv = false,
				},
			})

			local config = pyworks.get_config()

			assert.equals(false, config.python.use_uv, "user config should override default")
			assert.equals(".venv", config.python.preferred_venv_name, "defaults should be preserved")
		end)
	end)

	-- Creating a notebook installs the essentials into the project venv, so the
	-- Jupyter toolchain has to be in that list: jupytext to open .ipynb inside
	-- Neovim, jupyterlab to open the same notebook in the browser.
	describe("default python essentials", function()
		local function contains(list, value)
			for _, item in ipairs(list) do
				if item == value then
					return true
				end
			end
			return false
		end

		it("should include the jupyter toolchain needed to open notebooks", function()
			local pyworks = require("pyworks")
			pyworks.setup()

			local essentials = pyworks.get_config().python.essentials

			assert.is_true(contains(essentials, "jupytext"), "essentials should include jupytext")
			assert.is_true(contains(essentials, "jupyterlab"), "essentials should include jupyterlab")
		end)

		it("should hand the jupyter toolchain to the python module", function()
			local pyworks = require("pyworks")
			pyworks.setup()

			local essentials = require("pyworks.languages.python").get_essentials()

			assert.is_true(contains(essentials, "jupytext"), "python module should install jupytext")
			assert.is_true(contains(essentials, "jupyterlab"), "python module should install jupyterlab")
		end)

		-- vim.tbl_deep_extend merges arrays index-wise, so a shorter user list
		-- used to leave the tail of the defaults behind: setting
		-- essentials = { "pynvim" } still installed jupyterlab, numpy, pandas...
		it("should replace the essentials list instead of merging it index-wise", function()
			local pyworks = require("pyworks")
			pyworks.setup({ python = { essentials = { "pynvim" } } })

			local essentials = pyworks.get_config().python.essentials

			assert.are.same({ "pynvim" }, essentials)
		end)

		it("should hand the replaced list to the python module", function()
			local pyworks = require("pyworks")
			pyworks.setup({ python = { essentials = { "pynvim", "ipykernel" } } })

			local essentials = require("pyworks.languages.python").get_essentials()

			assert.are.same({ "pynvim", "ipykernel" }, essentials)
		end)

		it("should replace custom_package_prefixes instead of merging it", function()
			local pyworks = require("pyworks")
			pyworks.setup({ packages = { custom_package_prefixes = { "^acme_" } } })

			local prefixes = pyworks.get_config().packages.custom_package_prefixes

			assert.are.same({ "^acme_" }, prefixes)
		end)

		-- F1: the list lived in init.lua (8 entries) and languages/python.lua (5),
		-- hand-synced with nothing enforcing it. This fails the moment they part.
		it("should be the same list the python module defaults to", function()
			package.loaded["pyworks.languages.python"] = nil
			local module_default = require("pyworks.languages.python").get_essentials()

			package.loaded["pyworks"] = nil
			local pyworks = require("pyworks")
			pyworks.setup()
			local configured = pyworks.get_config().python.essentials

			for _, pkg in ipairs(module_default) do
				assert.is_true(
					contains(configured, pkg),
					string.format("%s is a module default but not in the configured list", pkg)
				)
			end
		end)

		it("should include jupyterlab even when setup() was never called", function()
			package.loaded["pyworks.languages.python"] = nil
			local python = require("pyworks.languages.python")

			local essentials = python.get_essentials()

			assert.is_true(contains(essentials, "jupytext"), "module default should include jupytext")
			assert.is_true(contains(essentials, "jupyterlab"), "module default should include jupyterlab")
		end)
	end)
end)
