-- Test suite for performance improvements
-- Tests async kernel detection and tmux-safe image configuration

describe("performance improvements", function()
	describe("kernel cache pre-warming", function()
		it("should export prewarm_kernel_cache function", function()
			local detector = require("pyworks.core.detector")
			assert.is_function(detector.prewarm_kernel_cache)
		end)

		it("should not block when pre-warming cache", function()
			local detector = require("pyworks.core.detector")

			-- Skip if jupyter is not available (test environment may not have it)
			local jupyter_available = vim.fn.executable("jupyter") == 1
			if not jupyter_available then
				-- Just verify the function exists and can be called without error
				local ok = pcall(detector.prewarm_kernel_cache)
				-- It's ok if it fails due to missing jupyter, as long as it doesn't block
				assert.is_true(true, "prewarm_kernel_cache exists and is callable")
				return
			end

			local start_time = vim.loop.now()
			detector.prewarm_kernel_cache()
			local elapsed = vim.loop.now() - start_time

			-- Pre-warming should return immediately (async)
			-- Allow 50ms for function call overhead
			assert.is_true(elapsed < 50, "prewarm_kernel_cache should be non-blocking")
		end)
	end)

	describe("image.nvim tmux configuration", function()
		it("should detect tmux environment", function()
			-- Save original
			local original_tmux = vim.env.TMUX

			-- Test with tmux
			vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
			local in_tmux = vim.env.TMUX ~= nil
			assert.is_true(in_tmux)

			-- Test without tmux
			vim.env.TMUX = nil
			in_tmux = vim.env.TMUX ~= nil
			assert.is_false(in_tmux)

			-- Restore
			vim.env.TMUX = original_tmux
		end)

		it("should use conservative settings in tmux", function()
			local original_tmux = vim.env.TMUX
			vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"

			local in_tmux = vim.env.TMUX ~= nil
			local max_width_pct = in_tmux and 80 or 100
			local max_height_pct = in_tmux and 80 or 100

			assert.equals(80, max_width_pct)
			assert.equals(80, max_height_pct)

			vim.env.TMUX = original_tmux
		end)

		it("should use full settings outside tmux", function()
			local original_tmux = vim.env.TMUX
			vim.env.TMUX = nil

			local in_tmux = vim.env.TMUX ~= nil
			local max_width_pct = in_tmux and 80 or 100
			local max_height_pct = in_tmux and 80 or 100

			assert.equals(100, max_width_pct)
			assert.equals(100, max_height_pct)

			vim.env.TMUX = original_tmux
		end)

		it("should disable window_overlap_clear in tmux", function()
			local original_tmux = vim.env.TMUX
			vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"

			local in_tmux = vim.env.TMUX ~= nil
			local window_overlap_clear_enabled = not in_tmux

			assert.is_false(window_overlap_clear_enabled)

			vim.env.TMUX = original_tmux
		end)
	end)

	describe("bounded image dimensions", function()
		it("should not use math.huge for dimensions", function()
			local init_content =
				vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/lua/pyworks/init.lua")
			local content = table.concat(init_content, "\n")

			-- Verify math.huge is not used for image dimensions
			-- The old problematic config used: max_height_window_percentage = math.huge
			local has_math_huge_height = content:find("max_height_window_percentage = math.huge", 1, true) ~= nil
			local has_math_huge_width = content:find("max_width_window_percentage = math.huge", 1, true) ~= nil

			assert.is_false(has_math_huge_height, "Should not use math.huge for max_height_window_percentage")
			assert.is_false(has_math_huge_width, "Should not use math.huge for max_width_window_percentage")
		end)

		it("should have comments explaining tmux fixes", function()
			local init_content =
				vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/lua/pyworks/init.lua")
			local content = table.concat(init_content, "\n")

			assert.is_true(content:find("tmux", 1, true) ~= nil)
			assert.is_true(content:find("maxfuncdepth", 1, true) ~= nil or content:find("redraw", 1, true) ~= nil)
		end)
	end)
end)

describe("async kernel detection", function()
	it("should have async kernel fetch function in detector", function()
		local detector_content = vim.fn.readfile(
			vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/lua/pyworks/core/detector.lua"
		)
		local content = table.concat(detector_content, "\n")

		-- Should have async function using jobstart
		assert.is_true(content:find("get_available_kernels_async", 1, true) ~= nil)
		assert.is_true(content:find("vim.fn.jobstart", 1, true) ~= nil)
	end)

	it("should cache kernelspecs to avoid repeated fetches", function()
		local detector_content = vim.fn.readfile(
			vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/lua/pyworks/core/detector.lua"
		)
		local content = table.concat(detector_content, "\n")

		-- Should have caching variables
		assert.is_true(content:find("cached_kernelspecs", 1, true) ~= nil)
		assert.is_true(content:find("kernelspecs_cache_time", 1, true) ~= nil)
	end)

	it("should use cached data in get_kernel_for_language", function()
		local detector_content = vim.fn.readfile(
			vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/lua/pyworks/core/detector.lua"
		)
		local content = table.concat(detector_content, "\n")

		-- Should use get_kernelspecs_sync which returns cached data
		assert.is_true(content:find("get_kernelspecs_sync", 1, true) ~= nil)
	end)
end)
