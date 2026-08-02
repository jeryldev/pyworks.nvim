-- Test suite for pyworks.core.state
--
-- First dedicated spec for this module: it persists to disk and drives the
-- environment-check throttle, so a fault here is silent. C4 covers a corrupt
-- state file breaking setup() outright, verified before the fix:
--   pairs() over a decoded `null` -> bad argument #1 to 'pairs' (got userdata)

local state = require("pyworks.core.state")

describe("state", function()
	describe("get / set / remove", function()
		before_each(function()
			state.remove("test_key")
		end)

		it("should store and return a value", function()
			state.set("test_key", 42)

			assert.are.equal(42, state.get("test_key"))
		end)

		it("should return nil for an unknown key", function()
			assert.is_nil(state.get("never_set_key"))
		end)

		it("should remove a value", function()
			state.set("test_key", "x")

			state.remove("test_key")

			assert.is_nil(state.get("test_key"))
		end)

		it("should reject a non-string key", function()
			assert.is_false(pcall(state.get, 42))
		end)
	end)

	describe("throttling", function()
		it("should allow a check that has never run", function()
			state.remove("last_check_probe_python")

			assert.is_true(state.should_check("probe", "python", 30))
		end)

		it("should block a repeat check inside the interval", function()
			state.set_last_check("probe", "python")

			assert.is_false(state.should_check("probe", "python", 30))
		end)

		it("should allow a check once the interval has passed", function()
			-- set_last_check always stamps "now", so age the entry directly
			state.set("last_check_probe_python", os.time() - 60)

			assert.is_true(state.should_check("probe", "python", 30))
		end)
	end)

	describe("persistence", function()
		-- Point the store at a temp file: writing to the real stdpath("data")
		-- depends on that directory existing, which it may not on a fresh
		-- machine (this failed on CI), and tests must not touch user data
		local state_file
		local real_file = state.get_state_file()

		before_each(function()
			state_file = vim.fn.tempname()
			state.configure({ file = state_file })
		end)

		after_each(function()
			vim.fn.delete(state_file)
			state.configure({ file = real_file })
		end)

		-- C4: load_persistent_state returned whatever vim.json.decode produced,
		-- and init() called pairs() on it. A truncated or `null` file - entirely
		-- possible, since the file is written from a debounced timer that does
		-- not survive a hard exit - threw during setup().
		it("should survive a state file containing null", function()
			vim.fn.writefile({ "null" }, state_file)

			assert.is_true(pcall(state.init))
		end)

		it("should survive a truncated state file", function()
			vim.fn.writefile({ '{"initialized_python_env": tr' }, state_file)

			assert.is_true(pcall(state.init))
		end)

		it("should survive a state file holding a JSON array", function()
			vim.fn.writefile({ "[1,2,3]" }, state_file)

			assert.is_true(pcall(state.init))
		end)

		it("should survive an empty state file", function()
			vim.fn.writefile({ "" }, state_file)

			assert.is_true(pcall(state.init))
		end)

		it("should load persisted keys from a valid file", function()
			vim.fn.writefile({ '{"initialized_probe_env": true}' }, state_file)

			state.init()

			assert.is_true(state.get("initialized_probe_env"))
		end)
	end)
end)
