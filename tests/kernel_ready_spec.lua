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
end)
