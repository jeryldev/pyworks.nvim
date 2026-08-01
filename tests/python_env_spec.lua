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
		it("should report completion when nothing is missing", function()
			-- "json" is stdlib, so the import check always succeeds and no
			-- install is spawned: the callback must still fire
			python.configure({ essentials = { "json" } })

			local completed = nil
			python.install_essentials(vim.fn.getcwd() .. "/probe.py", function(ok)
				completed = ok
			end)

			assert.is_true(completed)
		end)

		it("should not require a callback", function()
			python.configure({ essentials = { "json" } })

			local ok = pcall(python.install_essentials, vim.fn.getcwd() .. "/probe.py")

			assert.is_true(ok)
		end)
	end)
end)
