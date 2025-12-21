-- Test suite for pyworks.init module
-- Tests the configure_dependencies function and jupytext setup race condition fix

local pyworks = require("pyworks")

describe("pyworks.init", function()
	describe("configure_dependencies", function()
		it("should update PATH with venv bin directories", function()
			local temp_project = vim.fn.tempname()
			vim.fn.mkdir(temp_project .. "/.venv/bin", "p")

			local original_cwd = vim.fn.getcwd()
			vim.cmd("cd " .. temp_project)
			local original_path = vim.env.PATH

			pyworks.configure_dependencies({})

			local updated_path = vim.env.PATH
			assert.is_true(updated_path:find(temp_project .. "/.venv/bin", 1, true) ~= nil)

			vim.env.PATH = original_path
			vim.cmd("cd " .. original_cwd)
			vim.fn.delete(temp_project, "rf")
		end)

		it("should update PATH with parent venv bin directories", function()
			local parent_project = vim.fn.tempname()
			local subdir = parent_project .. "/subdir"
			vim.fn.mkdir(parent_project .. "/.venv/bin", "p")
			vim.fn.mkdir(subdir, "p")

			local original_cwd = vim.fn.getcwd()
			vim.cmd("cd " .. subdir)
			local original_path = vim.env.PATH

			pyworks.configure_dependencies({})

			local updated_path = vim.env.PATH
			assert.is_true(updated_path:find(parent_project .. "/.venv/bin", 1, true) ~= nil)

			vim.env.PATH = original_path
			vim.cmd("cd " .. original_cwd)
			vim.fn.delete(parent_project, "rf")
		end)

		it("should NOT call jupytext.setup() to prevent race conditions", function()
			local jupytext_setup_called = false
			local original_pcall = pcall

			local mock_jupytext = {
				setup = function()
					jupytext_setup_called = true
				end,
			}

			local original_require = require
			_G.require = function(module_name)
				if module_name == "jupytext" then
					return mock_jupytext
				end
				return original_require(module_name)
			end

			pyworks.configure_dependencies({ skip_jupytext = false })

			_G.require = original_require

			assert.is_false(jupytext_setup_called)
		end)

		it("should skip jupytext PATH update when skip_jupytext is true", function()
			local temp_project = vim.fn.tempname()
			vim.fn.mkdir(temp_project .. "/.venv/bin", "p")

			local original_cwd = vim.fn.getcwd()
			vim.cmd("cd " .. temp_project)
			local original_path = vim.env.PATH

			pyworks.configure_dependencies({ skip_jupytext = true })

			local updated_path = vim.env.PATH
			assert.equals(original_path, updated_path)

			vim.cmd("cd " .. original_cwd)
			vim.fn.delete(temp_project, "rf")
		end)

		it("should handle conda environment PATH", function()
			local temp_conda = vim.fn.tempname()
			vim.fn.mkdir(temp_conda .. "/bin", "p")

			local original_conda = vim.env.CONDA_PREFIX
			vim.env.CONDA_PREFIX = temp_conda
			local original_path = vim.env.PATH

			pyworks.configure_dependencies({})

			local updated_path = vim.env.PATH
			assert.is_true(updated_path:find(temp_conda .. "/bin", 1, true) ~= nil)

			vim.env.PATH = original_path
			vim.env.CONDA_PREFIX = original_conda
			vim.fn.delete(temp_conda, "rf")
		end)

		-- Note: PATH deduplication is not currently implemented
		-- This test documents expected behavior for future improvement
		pending("should not duplicate PATH entries on multiple calls", function()
			local temp_project = vim.fn.tempname()
			vim.fn.mkdir(temp_project .. "/.venv/bin", "p")

			local original_cwd = vim.fn.getcwd()
			vim.cmd("cd " .. temp_project)
			local original_path = vim.env.PATH

			pyworks.configure_dependencies({})

			pyworks.configure_dependencies({})
			local path_after_second = vim.env.PATH

			local venv_bin = temp_project .. "/.venv/bin"
			local first_pos = path_after_second:find(venv_bin, 1, true)
			local second_pos = path_after_second:find(venv_bin, first_pos + 1, true)

			assert.is_not_nil(first_pos)
			assert.is_nil(second_pos)

			vim.env.PATH = original_path
			vim.cmd("cd " .. original_cwd)
			vim.fn.delete(temp_project, "rf")
		end)
	end)
end)

describe("jupytext race condition prevention", function()
	it("should document that jupytext.setup is not called in configure_dependencies", function()
		local init_content =
			vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/lua/pyworks/init.lua")
		local content = table.concat(init_content, "\n")

		-- Check that the comment explains jupytext.setup is not called here
		assert.is_true(
			content:find("jupytext.setup", 1, true) ~= nil and content:find("NOT called here", 1, true) ~= nil,
			"Should have comment about jupytext.setup not being called"
		)
	end)

	it("should have comment explaining the race condition", function()
		local init_content =
			vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/lua/pyworks/init.lua")
		local content = table.concat(init_content, "\n")

		assert.is_true(content:find("race condition", 1, true) ~= nil)
		assert.is_true(content:find("BufWriteCmd", 1, true) ~= nil)
	end)

	it("should mention orphaned handlers as the cause", function()
		local init_content =
			vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/lua/pyworks/init.lua")
		local content = table.concat(init_content, "\n")

		assert.is_true(content:find("orphaned", 1, true) ~= nil)
	end)
end)
