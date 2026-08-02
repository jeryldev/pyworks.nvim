-- Test suite for tests/helpers/project.lua
--
-- The fixture exists because a spec that pointed at the repo made
-- install_essentials create a .venv in the checkout on CI, which then broke an
-- unrelated integration test (fixed in a1417c2). These tests keep that from
-- coming back.

local helpers = require("helpers.project")

describe("test helpers", function()
	describe("temp_project", function()
		it("should create an isolated directory with a written probe file", function()
			local project = helpers.temp_project()

			assert.are.equal(1, vim.fn.isdirectory(project.root))
			-- the file must exist on disk: get_project_paths falls back to cwd
			-- for an unreadable path, which would retarget the whole call
			assert.are.equal(1, vim.fn.filereadable(project.file))

			project.cleanup()
		end)

		it("should resolve as its own project root", function()
			local utils = require("pyworks.utils")
			local project = helpers.temp_project()

			local root = utils.find_project_root(vim.fn.fnamemodify(project.file, ":h"))

			assert.are.equal(vim.fn.resolve(project.root), vim.fn.resolve(root))
			project.cleanup()
		end)

		it("should create a working fake venv when asked", function()
			local project = helpers.temp_project({ fake_venv = true })

			assert.are.equal(1, vim.fn.isdirectory(project.venv))
			assert.are.equal(1, vim.fn.executable(project.python))

			local python = require("pyworks.languages.python")
			assert.is_true(python.has_venv(project.file))
			assert.is_true(python.is_package_installed("json", project.file))

			project.cleanup()
		end)

		it("should omit the venv by default", function()
			local project = helpers.temp_project()

			assert.are.equal(0, vim.fn.isdirectory(project.root .. "/.venv"))

			project.cleanup()
		end)

		it("should give each project a distinct root", function()
			local a = helpers.temp_project()
			local b = helpers.temp_project()

			assert.are_not.equal(a.root, b.root)

			a.cleanup()
			b.cleanup()
		end)

		it("should remove everything on cleanup", function()
			local project = helpers.temp_project({ fake_venv = true })
			local root = project.root

			project.cleanup()

			assert.are.equal(0, vim.fn.isdirectory(root))
		end)

		-- The actual regression: nothing may be created in the working directory
		it("should not touch the current working directory", function()
			local cwd_venv = vim.fn.getcwd() .. "/.venv"
			local existed_before = vim.fn.isdirectory(cwd_venv)

			local project = helpers.temp_project({ fake_venv = true })
			local python = require("pyworks.languages.python")
			python.is_package_installed("json", project.file)
			project.cleanup()

			assert.are.equal(existed_before, vim.fn.isdirectory(cwd_venv))
		end)
	end)

	describe("env_tests_enabled", function()
		it("should report a boolean", function()
			assert.is_boolean(helpers.env_tests_enabled())
		end)

		it("should follow PYWORKS_TEST_ENV", function()
			local saved = vim.env.PYWORKS_TEST_ENV

			vim.env.PYWORKS_TEST_ENV = "1"
			assert.is_true(helpers.env_tests_enabled())

			vim.env.PYWORKS_TEST_ENV = nil
			assert.is_false(helpers.env_tests_enabled())

			vim.env.PYWORKS_TEST_ENV = saved
		end)
	end)
end)
