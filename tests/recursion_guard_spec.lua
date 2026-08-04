-- Test suite for pyworks.core.recursion_guard
--
-- Ported from tests/test_recursion_guard.lua, which was written as a standalone
-- script and therefore never ran: the harness only collects *_spec.lua. This
-- module exists because notebook reload autocmds re-enter each other until
-- E132, so it is exactly the code that needs a regression net.

local guard = require("pyworks.core.recursion_guard")

describe("recursion_guard", function()
	before_each(function()
		guard.force_reset()
		guard.configure({ debounce_ms = 500, max_recursion_depth = 3 })
		vim.g.molten_tick_rate = 100
	end)

	after_each(function()
		guard.force_reset()
	end)

	describe("can_reload", function()
		it("should allow a reload initially", function()
			assert.is_true(guard.can_reload(1))
		end)

		it("should block while a global reload is in progress", function()
			guard.begin_reload(1)

			assert.is_false(guard.can_reload(2))
		end)

		it("should block a buffer that is already reloading", function()
			local release = guard.begin_reload(1)
			release()

			-- the per-buffer lock is cleared, but the debounce still applies
			assert.is_false(guard.can_reload(1))
		end)

		it("should block rapid successive reloads via the debounce", function()
			local release = guard.begin_reload(1)
			release()

			assert.is_false(guard.can_reload(1))
		end)

		-- C3: the debounce timestamp was global, so opening two notebooks within
		-- 500ms silently skipped converting the second one.
		it("should debounce per buffer, not globally", function()
			local release = guard.begin_reload(1)
			release()

			assert.is_false(guard.can_reload(1), "same buffer is still debounced")
			assert.is_true(guard.can_reload(2), "a different buffer may reload immediately")
		end)

		it("should stop recursion at the configured depth", function()
			guard.configure({ max_recursion_depth = 2 })
			guard.begin_reload(1)
			guard.begin_reload(2)

			assert.is_false(guard.can_reload(3))
		end)
	end)

	describe("begin_reload / end_reload", function()
		it("should release the global lock once every reload ends", function()
			local release = guard.begin_reload(1)
			assert.is_true(guard.is_reloading())

			release()

			assert.is_false(guard.is_reloading())
		end)

		it("should hold the lock until nested reloads unwind", function()
			local release_outer = guard.begin_reload(1)
			local release_inner = guard.begin_reload(2)

			release_inner()
			assert.is_true(guard.is_reloading(), "still reloading at depth 1")

			release_outer()
			assert.is_false(guard.is_reloading())
		end)

		it("should never take the depth below zero", function()
			guard.end_reload(1)
			guard.end_reload(1)

			assert.are.equal(0, guard.get_state().recursion_depth)
		end)

		it("should report which buffers are reloading", function()
			local release = guard.begin_reload(7)

			assert.is_true(guard.is_buffer_reloading(7))
			assert.is_false(guard.is_buffer_reloading(8))

			release()
			assert.is_false(guard.is_buffer_reloading(7))
		end)
	end)

	-- The guard used to raise g:molten_tick_rate to 999999 for the duration of a
	-- reload and restore it after. Restoring it is not enough, and no amount of
	-- care with the unwind makes it safe: Molten reads that variable exactly
	-- once, when its host initialises, and bakes it into timer_start(). A Molten
	-- that initialises inside the window keeps a timer firing every 16.7 minutes
	-- while the variable reads a healthy 100 forever after.
	--
	-- That is issue #10. The reporter's kernel was noticed 1999 seconds after
	-- MoltenInit; two ticks of 999999ms is 1999.998. Reproduced in the container:
	-- with the raise, ready=false after 45s and the timer at 999999ms; without
	-- it, ready in 1531ms at 100ms.
	--
	-- Nothing replaces it, because nothing needs to: the fork pyworks ships
	-- carries a MoltenTick reentrancy guard, which is what the raise was working
	-- around, and :checkhealth warns anyone running a Molten without it.
	describe("molten tick rate", function()
		it("should not touch the tick rate during a reload", function()
			vim.g.molten_tick_rate = 100

			local release = guard.begin_reload(1)
			assert.are.equal(100, vim.g.molten_tick_rate)

			release()
			assert.are.equal(100, vim.g.molten_tick_rate)
		end)

		it("should not touch the tick rate across nested reloads", function()
			vim.g.molten_tick_rate = 100

			local release_outer = guard.begin_reload(1)
			local release_inner = guard.begin_reload(2)
			assert.are.equal(100, vim.g.molten_tick_rate)
			release_inner()
			release_outer()

			assert.are.equal(100, vim.g.molten_tick_rate)
		end)

		it("should not touch the tick rate on force_reset", function()
			vim.g.molten_tick_rate = 100
			guard.begin_reload(1)

			guard.force_reset()

			assert.are.equal(100, vim.g.molten_tick_rate)
		end)
	end)

	describe("force_reset", function()
		it("should clear every lock", function()
			guard.begin_reload(1)
			guard.begin_reload(2)

			guard.force_reset()

			assert.is_false(guard.is_reloading())
			assert.is_false(guard.is_buffer_reloading(1))
			assert.are.equal(0, guard.get_state().recursion_depth)
			assert.is_true(guard.can_reload(1))
		end)
	end)

	describe("release under error", function()
		it("should still release when the guarded work throws", function()
			local release = guard.begin_reload(1)

			pcall(function()
				error("boom")
			end)
			release()

			assert.is_false(guard.is_reloading())
		end)
	end)
end)
