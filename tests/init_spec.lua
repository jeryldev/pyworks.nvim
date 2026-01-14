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

		it("should register PyworksDiagnostics command when diagnostics module is loaded", function()
			-- PyworksDiagnostics is defined in diagnostics.lua, which is lazy-loaded
			-- It's not registered during setup(), only when the module is required
			require("pyworks.diagnostics")

			local exists = vim.fn.exists(":PyworksDiagnostics") == 2

			assert.is_true(exists, "PyworksDiagnostics command should be registered after loading diagnostics module")
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
end)
