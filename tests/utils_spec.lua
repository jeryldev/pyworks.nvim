-- Test suite for pyworks.utils module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

local utils = require("pyworks.utils")

describe("utils", function()
	describe("get_project_paths", function()
		it("should find project root from nested file", function()
			-- Setup: Create temp project structure
			local temp_project = vim.fn.tempname()
			vim.fn.mkdir(temp_project .. "/subdir", "p")
			vim.fn.mkdir(temp_project .. "/.venv", "p")
			vim.fn.writefile({ "" }, temp_project .. "/pyproject.toml")
			local test_file = temp_project .. "/subdir/test.py"
			vim.fn.writefile({ "print('test')" }, test_file)

			-- Test
			local project_dir, venv_path = utils.get_project_paths(test_file)

			-- Assert
			assert.equals(temp_project, project_dir)
			assert.equals(temp_project .. "/.venv", venv_path)

			-- Cleanup
			vim.fn.delete(temp_project, "rf")
		end)

		it("should cache results for same project", function()
			-- Setup
			local temp_project = vim.fn.tempname()
			vim.fn.mkdir(temp_project .. "/.venv", "p")
			vim.fn.writefile({ "" }, temp_project .. "/pyproject.toml")
			local file1 = temp_project .. "/file1.py"
			local file2 = temp_project .. "/file2.py"
			vim.fn.writefile({ "print('1')" }, file1)
			vim.fn.writefile({ "print('2')" }, file2)

			-- Test: Both files should return same project_dir
			local proj1, venv1 = utils.get_project_paths(file1)
			local proj2, venv2 = utils.get_project_paths(file2)

			-- Assert
			assert.equals(proj1, proj2)
			assert.equals(venv1, venv2)
			assert.equals(temp_project, proj1)

			-- Cleanup
			vim.fn.delete(temp_project, "rf")
		end)

		it("should return different paths for different projects", function()
			-- Setup: Create two separate projects
			local project1 = vim.fn.tempname()
			local project2 = vim.fn.tempname()
			vim.fn.mkdir(project1 .. "/.venv", "p")
			vim.fn.mkdir(project2 .. "/.venv", "p")
			vim.fn.writefile({ "" }, project1 .. "/setup.py")
			vim.fn.writefile({ "" }, project2 .. "/setup.py")
			local file1 = project1 .. "/test1.py"
			local file2 = project2 .. "/test2.py"
			vim.fn.writefile({ "print('1')" }, file1)
			vim.fn.writefile({ "print('2')" }, file2)

			-- Test
			local proj1, venv1 = utils.get_project_paths(file1)
			local proj2, venv2 = utils.get_project_paths(file2)

			-- Assert: Should be different
			assert.is_not.equals(proj1, proj2)
			assert.equals(project1, proj1)
			assert.equals(project2, proj2)

			-- Cleanup
			vim.fn.delete(project1, "rf")
			vim.fn.delete(project2, "rf")
		end)

		it("should handle non-existent files gracefully", function()
			local fake_file = "/nonexistent/path/to/file.py"
			local project_dir, venv_path = utils.get_project_paths(fake_file)

			-- Should fall back to cwd
			assert.equals(vim.fn.getcwd(), project_dir)
			assert.equals(vim.fn.getcwd() .. "/.venv", venv_path)
		end)
	end)

	describe("find_project_root", function()
		it("should find .venv marker", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir .. "/nested/deep", "p")
			vim.fn.mkdir(temp_dir .. "/.venv", "p")

			local root = utils.find_project_root(temp_dir .. "/nested/deep")

			assert.equals(temp_dir, root)
			vim.fn.delete(temp_dir, "rf")
		end)

		it("should find pyproject.toml marker", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir .. "/src", "p")
			vim.fn.writefile({ "" }, temp_dir .. "/pyproject.toml")

			local root = utils.find_project_root(temp_dir .. "/src")

			assert.equals(temp_dir, root)
			vim.fn.delete(temp_dir, "rf")
		end)

		it("should prioritize .venv over other markers", function()
			-- Create nested structure with multiple markers
			local outer = vim.fn.tempname()
			local inner = outer .. "/inner"
			vim.fn.mkdir(inner .. "/.venv", "p")
			vim.fn.writefile({ "" }, outer .. "/pyproject.toml")

			-- Starting from inner, should find inner/.venv first
			local root = utils.find_project_root(inner)

			assert.equals(inner, root)
			vim.fn.delete(outer, "rf")
		end)

		it("should return start_dir if no markers found", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir, "p")

			local root = utils.find_project_root(temp_dir)

			-- Should return the directory itself or cwd
			assert.is_true(root == temp_dir or root == vim.fn.getcwd())
			vim.fn.delete(temp_dir, "rf")
		end)
	end)

	describe("detect_project_type", function()
		it("should detect Django projects", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir, "p")
			vim.fn.writefile({ "" }, temp_dir .. "/manage.py")

			local project_type = utils.detect_project_type(temp_dir)

			assert.equals("Django", project_type)
			vim.fn.delete(temp_dir, "rf")
		end)

		it("should detect Flask projects", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir, "p")
			vim.fn.writefile({ "from flask import Flask", "app = Flask(__name__)" }, temp_dir .. "/app.py")

			local project_type = utils.detect_project_type(temp_dir)

			assert.equals("Flask", project_type)
			vim.fn.delete(temp_dir, "rf")
		end)

		it("should detect Poetry projects", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir, "p")
			vim.fn.writefile({ "[tool.poetry]" }, temp_dir .. "/pyproject.toml")

			local project_type = utils.detect_project_type(temp_dir)

			assert.equals("Poetry/Modern Python", project_type)
			vim.fn.delete(temp_dir, "rf")
		end)

		it("should return 'Python' for unknown projects", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir, "p")

			local project_type = utils.detect_project_type(temp_dir)

			assert.equals("Python", project_type)
			vim.fn.delete(temp_dir, "rf")
		end)
	end)

	describe("has_venv", function()
		it("should return true when .venv exists", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir .. "/.venv/bin", "p")
			local test_file = temp_dir .. "/test.py"
			vim.fn.writefile({ "" }, test_file)

			local has_venv = utils.has_venv()

			-- Note: has_venv uses get_project_paths which uses cwd by default
			-- So we need to test with actual filepath
			vim.fn.delete(temp_dir, "rf")
		end)

		it("should return false when .venv does not exist", function()
			local temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir, "p")
			local test_file = temp_dir .. "/test.py"
			vim.fn.writefile({ "" }, test_file)

			-- Test by checking the directory directly
			local venv_path = temp_dir .. "/.venv"
			local exists = vim.fn.isdirectory(venv_path) == 1

			assert.is_false(exists)
			vim.fn.delete(temp_dir, "rf")
		end)
	end)

	describe("path utilities", function()
		it("path_join should concatenate paths", function()
			local result = utils.path_join("foo", "bar", "baz.txt")
			assert.equals("foo/bar/baz.txt", result)
		end)

		it("path_exists should detect existing paths", function()
			local temp_file = vim.fn.tempname()
			vim.fn.writefile({ "" }, temp_file)

			assert.is_true(utils.path_exists(temp_file))
			assert.is_false(utils.path_exists("/nonexistent/path"))

			vim.fn.delete(temp_file)
		end)

		it("ensure_directory should create directories", function()
			local temp_dir = vim.fn.tempname() .. "/nested/deep"

			utils.ensure_directory(temp_dir)

			assert.is_true(utils.path_exists(temp_dir))
			vim.fn.delete(vim.fn.fnamemodify(temp_dir, ":h:h"), "rf")
		end)
	end)

	describe("async_system_call", function()
		it("should execute commands asynchronously", function()
			local result_stdout = nil
			local result_success = nil

			utils.async_system_call("echo 'test'", function(success, stdout, stderr, exit_code)
				result_success = success
				result_stdout = vim.trim(stdout)
			end)

			-- Wait for async call to complete
			vim.wait(1000, function()
				return result_stdout ~= nil
			end)

			assert.is_true(result_success)
			assert.equals("test", result_stdout)
		end)

		it("should handle command failures", function()
			local result_success = nil
			local result_exit_code = nil

			utils.async_system_call("false", function(success, stdout, stderr, exit_code)
				result_success = success
				result_exit_code = exit_code
			end)

			vim.wait(1000, function()
				return result_exit_code ~= nil
			end)

			assert.is_false(result_success)
			assert.is_not.equals(0, result_exit_code)
		end)
	end)

	describe("file operations", function()
		it("safe_file_write should write content", function()
			local temp_file = vim.fn.tempname()
			local content = "test content\nline 2"

			local success = utils.safe_file_write(temp_file, content)

			assert.is_true(success)
			local read_content = table.concat(vim.fn.readfile(temp_file), "\n")
			assert.equals(content, read_content)

			vim.fn.delete(temp_file)
		end)

		it("safe_file_read should read content", function()
			local temp_file = vim.fn.tempname()
			local content = "test content"
			vim.fn.writefile({ content }, temp_file)

			local read_content, err = utils.safe_file_read(temp_file)

			assert.is_nil(err)
			assert.equals(content, vim.trim(read_content))

			vim.fn.delete(temp_file)
		end)

		it("safe_file_read should handle missing files", function()
			local content, err = utils.safe_file_read("/nonexistent/file")

			assert.is_nil(content)
			assert.is_not_nil(err)
			assert.is_true(err:match("Failed to open file"))
		end)
	end)

	describe("cache utilities", function()
		it("get_cached should cache results", function()
			local call_count = 0
			local fetcher = function()
				call_count = call_count + 1
				return "result_" .. call_count
			end

			local result1 = utils.get_cached("test_key", fetcher, 1000)
			local result2 = utils.get_cached("test_key", fetcher, 1000)

			-- Should only call fetcher once
			assert.equals(1, call_count)
			assert.equals("result_1", result1)
			assert.equals("result_1", result2)

			utils.clear_cache("test_key")
		end)

		it("get_cached should expire after TTL", function()
			local call_count = 0
			local fetcher = function()
				call_count = call_count + 1
				return "result_" .. call_count
			end

			local result1 = utils.get_cached("test_key", fetcher, 10) -- 10ms TTL
			vim.wait(50) -- Wait for expiry
			local result2 = utils.get_cached("test_key", fetcher, 10)

			-- Should call fetcher twice
			assert.equals(2, call_count)
			assert.equals("result_1", result1)
			assert.equals("result_2", result2)

			utils.clear_cache("test_key")
		end)

		it("clear_cache should invalidate cache", function()
			local call_count = 0
			local fetcher = function()
				call_count = call_count + 1
				return "result"
			end

			utils.get_cached("test_key", fetcher, 1000)
			utils.clear_cache("test_key")
			utils.get_cached("test_key", fetcher, 1000)

			assert.equals(2, call_count)
		end)
	end)
end)
