-- Test suite for pyworks.core.kernel_ready
-- Molten announces readiness as a one-shot event; these tests cover the case
-- that broke issue #10 twice: the event arriving before we were listening or
-- before the buffer knew its kernel.

describe("kernel_ready", function()
	local kernel_ready
	local test_bufnr

	before_each(function()
		package.loaded["pyworks.core.kernel_ready"] = nil
		kernel_ready = require("pyworks.core.kernel_ready")
		kernel_ready._reset()
		kernel_ready.setup()

		test_bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(test_bufnr)
		vim.b[test_bufnr].molten_initialized = true
		vim.b[test_bufnr].pyworks_kernel_name = "test_kernel"
	end)

	after_each(function()
		if vim.api.nvim_buf_is_valid(test_bufnr) then
			vim.api.nvim_buf_delete(test_bufnr, { force = true })
		end
	end)

	describe("is_ready", function()
		it("should be false for a kernel that has not reported ready", function()
			assert.is_false(kernel_ready.is_ready(test_bufnr))
		end)

		it("should be true after the kernel reports ready", function()
			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "test_kernel" },
			})

			assert.is_true(kernel_ready.is_ready(test_bufnr))
		end)

		it("should stay false when a different kernel reports ready", function()
			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "other_kernel" },
			})

			assert.is_false(kernel_ready.is_ready(test_bufnr))
		end)

		-- The .ipynb case: jupytext conversion delays FileType python, so the
		-- kernel can report ready before the buffer is tagged with its name.
		it("should recognise a kernel that reported ready before the buffer was tagged", function()
			vim.b[test_bufnr].pyworks_kernel_name = nil
			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "late_kernel" },
			})
			vim.b[test_bufnr].pyworks_kernel_ready = nil
			vim.b[test_bufnr].pyworks_kernel_name = "late_kernel"

			assert.is_true(kernel_ready.is_ready(test_bufnr))
		end)
	end)

	-- These are reached from deferred callbacks, so the buffer may be gone by
	-- the time they run; vim.b[<invalid>] throws where nothing can catch it.
	describe("with a deleted buffer", function()
		it("is_ready should report false instead of erroring", function()
			local gone = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_delete(gone, { force = true })

			local ok, result = pcall(kernel_ready.is_ready, gone)

			assert.is_true(ok)
			assert.is_false(result)
		end)

		it("run_when_ready should not error", function()
			local gone = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_delete(gone, { force = true })

			local ok = pcall(kernel_ready.run_when_ready, gone, function() end, { timeout_ms = 50 })

			assert.is_true(ok)
		end)
	end)

	describe("run_when_ready", function()
		it("should run immediately when the kernel is already ready", function()
			kernel_ready.mark_ready("test_kernel")

			local ran = false
			kernel_ready.run_when_ready(test_bufnr, function()
				ran = true
			end)

			assert.is_true(ran)
		end)

		it("should hold the callback until the kernel reports ready", function()
			local ran = false

			kernel_ready.run_when_ready(test_bufnr, function()
				ran = true
			end)
			vim.wait(150, function()
				return ran
			end, 25)
			assert.is_false(ran)

			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "test_kernel" },
			})
			vim.wait(1000, function()
				return ran
			end, 25)

			assert.is_true(ran)
		end)

		it("should run the callback once the fallback elapses", function()
			local ran = false

			kernel_ready.run_when_ready(test_bufnr, function()
				ran = true
			end, { timeout_ms = 50 })
			vim.wait(1000, function()
				return ran
			end, 25)

			assert.is_true(ran)
		end)

		it("should run the callback only once", function()
			local runs = 0

			kernel_ready.run_when_ready(test_bufnr, function()
				runs = runs + 1
			end, { timeout_ms = 50 })
			vim.wait(500, function()
				return runs > 0
			end, 25)
			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "test_kernel" },
			})
			vim.wait(200, function()
				return runs > 1
			end, 25)

			assert.are.equal(1, runs)
		end)
	end)

	-- A kernel that never reports ready is the whole of issue #10 as the user
	-- experiences it: "Starting kernel..." and then nothing, forever. Molten
	-- reports its own startup failures asynchronously, so :MoltenInit returns
	-- success even when no kernel exists. Without a watchdog there is no moment
	-- at which pyworks admits something went wrong.
	describe("watch", function()
		it("should report a kernel that never becomes ready", function()
			local reported

			kernel_ready.watch(test_bufnr, "test_kernel", {
				timeout_ms = 50,
				on_timeout = function(kernel)
					reported = kernel
				end,
			})

			vim.wait(500, function()
				return reported ~= nil
			end, 25)

			assert.are.equal("test_kernel", reported)
		end)

		it("should stay quiet when the kernel reports ready in time", function()
			local reported = false

			kernel_ready.watch(test_bufnr, "test_kernel", {
				timeout_ms = 200,
				on_timeout = function()
					reported = true
				end,
			})
			vim.api.nvim_exec_autocmds("User", {
				pattern = "MoltenKernelReady",
				data = { kernel_id = "test_kernel" },
			})

			vim.wait(400)

			assert.is_false(reported)
		end)

		it("should stay quiet when the buffer is gone", function()
			local reported = false
			local doomed = vim.api.nvim_create_buf(false, true)

			kernel_ready.watch(doomed, "test_kernel", {
				timeout_ms = 50,
				on_timeout = function()
					reported = true
				end,
			})
			vim.api.nvim_buf_delete(doomed, { force = true })

			vim.wait(300)

			assert.is_false(reported)
		end)
	end)
end)
