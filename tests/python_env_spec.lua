-- Test suite for environment setup timing in pyworks.languages.python
-- Covers the two ways :PyworksSetup used to claim success without it being true:
-- the 30s throttle silently skipping the work, and "ready" being announced
-- while the package install was still running in the background.

describe("python environment setup", function()
	local python
	local state

	before_each(function()
		package.loaded["pyworks.languages.python"] = nil
		python = require("pyworks.languages.python")
		state = require("pyworks.core.state")
	end)

	describe("should_check_environment", function()
		it("should allow a check once the throttle window has passed", function()
			state.remove("last_check_python_env_python")

			assert.is_true(python.should_check_environment())
		end)

		it("should throttle a repeat check", function()
			state.set_last_check("python_env", "python")

			assert.is_false(python.should_check_environment())
		end)

		-- :PyworksSetup is an explicit request; a throttle meant to keep file
		-- open cheap must not turn it into a silent no-op that reports success
		it("should run anyway when forced", function()
			state.set_last_check("python_env", "python")

			assert.is_true(python.should_check_environment(true))
		end)
	end)

	describe("install_essentials completion", function()
		local project, probe

		-- A self-contained project: a .venv whose python is a symlink to the
		-- real interpreter. Pointing these tests at the repo would make
		-- install_essentials create a venv in the checkout on a machine that has
		-- none (CI), which then changes what later tests observe.
		before_each(function()
			project = vim.fn.tempname()
			vim.fn.mkdir(project .. "/.venv/bin", "p")
			vim.uv.fs_symlink(vim.fn.exepath("python3"), project .. "/.venv/bin/python")
			-- The file must exist: get_project_paths falls back to cwd for an
			-- unreadable path, which would point the whole call at the repo
			probe = project .. "/probe.py"
			vim.fn.writefile({ "print('probe')" }, probe)
			-- "json" is stdlib, so the import check always succeeds and no
			-- install is ever spawned
			python.configure({ essentials = { "json" } })
		end)

		after_each(function()
			vim.fn.delete(project, "rf")
		end)

		it("should report completion when nothing is missing", function()
			local completed = nil

			python.install_essentials(probe, function(ok)
				completed = ok
			end)

			assert.is_true(completed)
		end)

		it("should not require a callback", function()
			local ok = pcall(python.install_essentials, probe)

			assert.is_true(ok)
		end)
	end)
end)
