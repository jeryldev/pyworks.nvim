describe("python command security", function()
	local python

	before_each(function()
		package.loaded["pyworks.languages.python"] = nil
		python = require("pyworks.languages.python")
	end)

	describe("shell safety", function()
		it("should not contain sh -c wrapping pattern in python.lua", function()
			local source_path = "lua/pyworks/languages/python.lua"
			local lines = vim.fn.readfile(source_path)
			local source = table.concat(lines, "\n")
			assert.is_nil(source:match('"sh",%s*"-c"'), "python.lua should not use sh -c wrapping")
		end)

		it("should not contain sh -c wrapping pattern in utils.lua", function()
			local source_path = "lua/pyworks/utils.lua"
			local lines = vim.fn.readfile(source_path)
			local source = table.concat(lines, "\n")
			assert.is_nil(source:match('"sh",%s*"-c"'), "utils.lua should not use sh -c wrapping")
		end)
	end)

	describe("pip_path nil safety", function()
		it("get_pip_path should return nil when no venv exists", function()
			local result = python.get_pip_path("/nonexistent/path/file.py")
			assert.is_nil(result)
		end)
	end)
end)
