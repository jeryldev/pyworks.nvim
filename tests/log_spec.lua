-- Test suite for pyworks.core.log
-- The always-on ring buffer is the point: diagnostics must exist before a user
-- is asked to reproduce anything (issue #10 cost five round-trips).

describe("log", function()
	local log

	before_each(function()
		package.loaded["pyworks.core.log"] = nil
		log = require("pyworks.core.log")
		log.clear()
	end)

	describe("levels", function()
		it("should record entries at or above the configured level", function()
			log.configure({ level = "info" })

			log.info("mod", "kept")
			log.warn("mod", "kept too")

			assert.are.equal(2, #log.entries())
		end)

		it("should drop entries below the configured level", function()
			log.configure({ level = "warn" })

			log.debug("mod", "dropped")
			log.info("mod", "dropped")

			assert.are.equal(0, #log.entries())
		end)

		it("should record debug entries at the default level", function()
			log.configure({ level = nil })

			log.debug("mod", "kept by default")

			assert.are.equal(1, #log.entries())
		end)
	end)

	describe("entry contents", function()
		it("should capture level, module and formatted message", function()
			log.configure({ level = "debug" })

			log.warn("detector", "kernel %s uses %s", "k1", "/bin/python")
			local entry = log.entries()[1]

			assert.are.equal("warn", entry.level)
			assert.are.equal("detector", entry.module)
			assert.are.equal("kernel k1 uses /bin/python", entry.message)
			assert.is_number(entry.time)
		end)

		it("should attach context set via ctx", function()
			log.configure({ level = "debug" })
			log.ctx({ bufnr = 7, project = "/tmp/p" })

			log.debug("mod", "msg")
			local entry = log.entries()[1]

			assert.are.equal(7, entry.ctx.bufnr)
			assert.are.equal("/tmp/p", entry.ctx.project)
		end)

		it("should return entries oldest first", function()
			log.configure({ level = "debug" })

			log.debug("mod", "first")
			log.debug("mod", "second")
			local entries = log.entries()

			assert.are.equal("first", entries[1].message)
			assert.are.equal("second", entries[2].message)
		end)
	end)

	-- The property that keeps logging free when it is switched off: a disabled
	-- level must not even build the message. Today's debug_log() calls
	-- string.format eagerly, including three times per 150ms poll during run-all.
	describe("lazy formatting", function()
		it("should not evaluate arguments when the level is disabled", function()
			log.configure({ level = "error" })
			local evaluated = false
			local probe = setmetatable({}, {
				__tostring = function()
					evaluated = true
					return "expensive"
				end,
			})

			log.debug("mod", "value=%s", probe)

			assert.is_false(evaluated)
		end)

		it("should evaluate arguments when the level is enabled", function()
			log.configure({ level = "debug" })
			local evaluated = false
			local probe = setmetatable({}, {
				__tostring = function()
					evaluated = true
					return "expensive"
				end,
			})

			log.debug("mod", "value=%s", probe)

			assert.is_true(evaluated)
		end)
	end)

	describe("ring buffer", function()
		it("should keep only the most recent entries", function()
			log.configure({ level = "debug", max_entries = 3 })

			for i = 1, 5 do
				log.debug("mod", "entry %d", i)
			end
			local entries = log.entries()

			assert.are.equal(3, #entries)
			assert.are.equal("entry 3", entries[1].message)
			assert.are.equal("entry 5", entries[3].message)
		end)

		it("should be cleared by clear()", function()
			log.configure({ level = "debug" })
			log.debug("mod", "x")

			log.clear()

			assert.are.equal(0, #log.entries())
		end)
	end)

	describe("redaction", function()
		it("should replace the home directory in messages", function()
			log.configure({ level = "debug", redact = true })

			log.debug("mod", "path %s", vim.env.HOME .. "/secret/project")
			local entry = log.entries()[1]

			assert.is_nil(entry.message:find(vim.env.HOME, 1, true))
			assert.is_truthy(entry.message:find("~/secret/project", 1, true))
		end)

		it("should leave messages untouched when redaction is off", function()
			log.configure({ level = "debug", redact = false })

			log.debug("mod", "path %s", vim.env.HOME .. "/x")
			local entry = log.entries()[1]

			assert.is_truthy(entry.message:find(vim.env.HOME, 1, true))
		end)
	end)

	describe("file sink", function()
		local tmpfile

		before_each(function()
			tmpfile = vim.fn.tempname()
		end)

		after_each(function()
			vim.fn.delete(tmpfile)
		end)

		it("should not write anything when the sink is disabled", function()
			log.configure({ level = "debug", file = false, file_path = tmpfile })

			log.debug("mod", "not written")

			assert.are.equal(0, vim.fn.filereadable(tmpfile))
		end)

		it("should append entries when the sink is enabled", function()
			log.configure({ level = "debug", file = true, file_path = tmpfile })

			log.warn("mod", "written to file")

			assert.are.equal(1, vim.fn.filereadable(tmpfile))
			local content = table.concat(vim.fn.readfile(tmpfile), "\n")
			assert.is_truthy(content:find("written to file", 1, true))
			assert.is_truthy(content:find("mod", 1, true))
		end)

		it("should rotate when the file exceeds its size limit", function()
			log.configure({ level = "debug", file = true, file_path = tmpfile, max_file_bytes = 200 })

			for i = 1, 50 do
				log.debug("mod", "padding entry number %d with some length", i)
			end

			local size = vim.fn.getfsize(tmpfile)
			assert.is_true(size <= 200 * 2, "log file should be rotated, got " .. size .. " bytes")
		end)
	end)

	describe("format_entry", function()
		it("should render a readable single line", function()
			log.configure({ level = "debug" })
			log.warn("detector", "something happened")

			local line = log.format_entry(log.entries()[1])

			assert.is_truthy(line:find("WARN", 1, true))
			assert.is_truthy(line:find("detector", 1, true))
			assert.is_truthy(line:find("something happened", 1, true))
		end)
	end)
end)
