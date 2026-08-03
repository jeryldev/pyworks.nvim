-- Test suite for pyworks.dependencies
--
-- Pyworks ships a fork of molten (jeryldev/molten-nvim) carrying a MoltenTick
-- reentrancy guard and a dict-iteration fix that upstream lacks. A user who
-- already had benlubas/molten-nvim installed keeps it - lazy.nvim resolves by
-- plugin name, and their own spec wins - so they silently run without those
-- fixes. Pyworks cannot uninstall someone else's plugin, but it can say so.

local dependencies = require("pyworks.dependencies")

describe("dependencies", function()
	describe("molten fork detection", function()
		local function molten_tree(source)
			local root = vim.fn.tempname()
			vim.fn.mkdir(root .. "/rplugin/python3/molten", "p")
			vim.fn.writefile(source, root .. "/rplugin/python3/molten/__init__.py")
			return root
		end

		it("should recognise the fork by its reentrancy guard", function()
			local root = molten_tree({
				"class Molten:",
				"    _ticking = False",
				"    def function_molten_tick(self, _):",
				"        if self._ticking:",
				"            return",
			})

			assert.is_true(dependencies.has_reentrancy_guard(root))
			vim.fn.delete(root, "rf")
		end)

		it("should recognise upstream by the guard's absence", function()
			local root = molten_tree({
				"class Molten:",
				"    def function_molten_tick(self, _):",
				"        for m in self._get_current_buf_kernels(False):",
				"            m.tick()",
			})

			assert.is_false(dependencies.has_reentrancy_guard(root))
			vim.fn.delete(root, "rf")
		end)

		it("should report unknown for a directory that is not molten", function()
			assert.is_nil(dependencies.has_reentrancy_guard(vim.fn.tempname()))
		end)

		it("should treat a jeryldev url as the fork", function()
			assert.is_true(dependencies.is_fork_url("https://github.com/jeryldev/molten-nvim.git"))
			assert.is_true(dependencies.is_fork_url("jeryldev/molten-nvim"))
		end)

		it("should treat an upstream url as not the fork", function()
			assert.is_false(dependencies.is_fork_url("https://github.com/benlubas/molten-nvim.git"))
			assert.is_false(dependencies.is_fork_url("benlubas/molten-nvim"))
		end)

		it("should not claim a verdict without a url", function()
			assert.is_nil(dependencies.is_fork_url(nil))
			assert.is_nil(dependencies.is_fork_url(""))
		end)

		it("should describe the installed molten without throwing", function()
			local info = dependencies.molten_source()

			assert.is_table(info)
			assert.is_true(info.installed ~= nil)
		end)
	end)

	-- Molten only ever notices a kernel became ready from inside MoltenBuffer.tick(),
	-- which nothing calls but the repeating MoltenTick timer. That timer is created
	-- at the end of Molten's _initialize(), after canvas.init() - so if image
	-- provider setup throws, Molten stays half-initialised: :MoltenInit reports
	-- success, a kernel really does start, and nothing ever polls it. Cells then sit
	-- on "* On Hold" forever with no error anywhere (issue #10).
	describe("tick timer detection", function()
		local timer_id

		after_each(function()
			if timer_id then
				pcall(vim.fn.timer_stop, timer_id)
				timer_id = nil
			end
		end)

		it("should report no tick timer when Molten has not started one", function()
			assert.is_false(dependencies.molten_tick_timer().running)
		end)

		it("should detect the timer Molten starts", function()
			vim.cmd([[
				function! MoltenTick(t)
				endfunction
			]])
			-- started through eval() because that is how Molten does it, and
			-- because a Lua-registered callback is not visible to timer_info()
			timer_id = vim.fn.eval("timer_start(10000, 'MoltenTick', {'repeat': -1})")

			assert.is_true(dependencies.molten_tick_timer().running)
		end)

		it("should always answer with a table, never throw", function()
			-- this runs from a watchdog callback, where a throw would be unhandled
			local info = dependencies.molten_tick_timer()

			assert.is_table(info)
			assert.is_boolean(info.running)
		end)
	end)
end)
