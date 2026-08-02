-- Test suite for pyworks.core.notifications
--
-- First dedicated spec for the module that gates every user-facing message.
-- B1: with the default config only action_required/error/first_time/progress
-- messages reached the user - plain INFO *and WARN* were dropped, including
-- "Ignoring stale kernel..." and "Installing...". Verified before the fix:
--   shown with DEFAULT config: { "action required" }

describe("notifications", function()
	local notifications
	local shown

	local function capture()
		shown = {}
		local real = vim.notify
		vim.notify = function(msg, level)
			table.insert(shown, { msg = msg, level = level })
		end
		return function()
			vim.notify = real
		end
	end

	before_each(function()
		package.loaded["pyworks.core.notifications"] = nil
		notifications = require("pyworks.core.notifications")
		notifications.clear_history()
	end)

	describe("level handling with the default config", function()
		before_each(function()
			notifications.configure({
				verbose_first_time = true,
				silent_when_ready = true,
				show_progress = true,
				debug_mode = false,
			})
		end)

		it("should show warnings", function()
			local restore = capture()
			notifications.notify("stale kernel ignored", vim.log.levels.WARN)
			restore()

			assert.are.equal(1, #shown)
			assert.are.equal("stale kernel ignored", shown[1].msg)
		end)

		it("should show errors", function()
			local restore = capture()
			notifications.notify("something failed", vim.log.levels.ERROR)
			restore()

			assert.are.equal(1, #shown)
		end)

		it("should suppress routine info", function()
			local restore = capture()
			notifications.notify("routine chatter", vim.log.levels.INFO)
			restore()

			assert.are.equal(0, #shown)
		end)

		it("should still show info flagged as action_required", function()
			local restore = capture()
			notifications.notify("do something", vim.log.levels.INFO, { action_required = true })
			restore()

			assert.are.equal(1, #shown)
		end)
	end)

	describe("silent_when_ready disabled", function()
		it("should show info too", function()
			notifications.configure({ silent_when_ready = false })

			local restore = capture()
			notifications.notify("now visible", vim.log.levels.INFO)
			restore()

			assert.are.equal(1, #shown)
		end)
	end)

	describe("deduplication", function()
		it("should collapse an identical repeat", function()
			notifications.configure({ silent_when_ready = true })

			local restore = capture()
			notifications.notify("same warning", vim.log.levels.WARN)
			notifications.notify("same warning", vim.log.levels.WARN)
			restore()

			assert.are.equal(1, #shown)
		end)

		it("should not collapse different messages", function()
			local restore = capture()
			notifications.notify("first warning", vim.log.levels.WARN)
			notifications.notify("second warning", vim.log.levels.WARN)
			restore()

			assert.are.equal(2, #shown)
		end)
	end)

	-- B2: the flag was keyed by language alone and persisted, so after the first
	-- successful setup on a machine the message never appeared again in any
	-- project. This machine's initialized_python_env dates from January 2026.
	describe("environment ready messages", function()
		local state = require("pyworks.core.state")

		before_each(function()
			state.remove("initialized_python_env")
			state.remove("initialized_python_env_/tmp/project_a")
			state.remove("initialized_python_env_/tmp/project_b")
		end)

		it("should announce readiness once for a project", function()
			local restore = capture()
			notifications.notify_environment_ready("python", "/tmp/project_a")
			notifications.notify_environment_ready("python", "/tmp/project_a")
			restore()

			assert.are.equal(1, #shown)
		end)

		it("should announce again for a different project", function()
			local restore = capture()
			notifications.notify_environment_ready("python", "/tmp/project_a")
			notifications.notify_environment_ready("python", "/tmp/project_b")
			restore()

			assert.are.equal(2, #shown)
			assert.is_truthy(shown[1].msg:find("project_a", 1, true))
			assert.is_truthy(shown[2].msg:find("project_b", 1, true))
		end)
	end)
end)
