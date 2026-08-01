-- Test suite for pyworks.report (:PyworksReport / :PyworksLog)
-- Issue #10 needed five round-trips to collect information the plugin already
-- had. This produces all of it in one paste.

describe("report", function()
	local report, log

	before_each(function()
		package.loaded["pyworks.report"] = nil
		package.loaded["pyworks.core.log"] = nil
		log = require("pyworks.core.log")
		log.reset()
		report = require("pyworks.report")
	end)

	describe("generate", function()
		it("should include every documented section", function()
			local text = report.generate()

			for _, heading in ipairs({ "## Environment", "## Kernels", "## Packages", "## Health", "## Recent log" }) do
				assert.is_truthy(text:find(heading, 1, true), "missing section: " .. heading)
			end
		end)

		it("should include the recent log entries", function()
			log.warn("detector", "a distinctive log line")

			local text = report.generate()

			assert.is_truthy(text:find("a distinctive log line", 1, true))
		end)

		it("should redact the home directory by default", function()
			log.configure({ redact = false })
			log.info("mod", "path %s", vim.env.HOME .. "/private/thing")

			local text = report.generate()

			assert.is_nil(text:find(vim.env.HOME, 1, true))
		end)

		it("should keep home paths when redaction is disabled", function()
			log.configure({ redact = false })
			log.info("mod", "path %s", vim.env.HOME .. "/private/thing")

			local text = report.generate({ redact = false })

			assert.is_truthy(text:find(vim.env.HOME, 1, true))
		end)

		it("should report the neovim and plugin versions", function()
			local text = report.generate()

			assert.is_truthy(text:find("nvim", 1, true))
		end)

		-- The check that would have short-circuited issue #10's first hypothesis
		it("should state whether each kernel interpreter still exists", function()
			local text = report.generate()

			assert.is_truthy(text:find("Kernels", 1, true))
			-- either kernels are listed with an exists marker, or jupyter was unavailable
			local has_marker = text:find("interpreter exists", 1, true) or text:find("unavailable", 1, true)
			assert.is_truthy(has_marker)
		end)

		it("should not throw when jupyter and the venv are absent", function()
			local ok = pcall(report.generate, { project_dir = "/nonexistent/project" })

			assert.is_true(ok)
		end)
	end)

	describe("commands", function()
		it("should register PyworksReport and PyworksLog", function()
			report.setup_commands()

			assert.are.equal(2, vim.fn.exists(":PyworksReport"))
			assert.are.equal(2, vim.fn.exists(":PyworksLog"))
		end)
	end)
end)
