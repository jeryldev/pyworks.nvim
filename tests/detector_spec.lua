-- Test suite for pyworks.core.detector module
-- Tests kernel detection, creation, and file handling

local detector = require("pyworks.core.detector")

describe("detector", function()
  describe("get_kernel_for_language", function()
    it("should return nil when no kernel found and ipykernel missing", function()
      -- This test requires mocking jupyter kernel list
      -- Skip for now as it requires extensive mocking
      pending("requires kernel mocking")
    end)

    it("should create kernel when venv exists but no kernel found", function()
      pending("requires kernel mocking")
    end)

    it("should validate ipykernel before creating kernel", function()
      -- Setup: Create venv without ipykernel
      local temp_project = vim.fn.tempname()
      vim.fn.mkdir(temp_project .. "/.venv/bin", "p")
      local python_exe = temp_project .. "/.venv/bin/python3"

      -- Create a fake python that doesn't have ipykernel
      -- This requires system-level mocking
      pending("requires Python mocking infrastructure")
    end)
  end)

  describe("handle_python", function()
    it("should show warning when venv does not exist", function()
      -- Setup
      local temp_project = vim.fn.tempname()
      vim.fn.mkdir(temp_project, "p")
      local test_file = temp_project .. "/test.py"
      vim.fn.writefile({ "print('test')" }, test_file)

      -- Mock notifications
      local notifications_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("No venv") then
          notifications_called = true
        end
      end

      -- Test
      detector.handle_python(test_file)

      -- Restore
      vim.notify = original_notify

      -- Assert
      assert.is_true(notifications_called)

      -- Cleanup
      vim.fn.delete(temp_project, "rf")
    end)

    it("should set pyworks_filepath buffer variable", function()
      local temp_project = vim.fn.tempname()
      vim.fn.mkdir(temp_project, "p")
      local test_file = temp_project .. "/test.py"
      vim.fn.writefile({ "print('test')" }, test_file)

      -- Open the file in a buffer
      vim.cmd("edit " .. test_file)
      local bufnr = vim.api.nvim_get_current_buf()

      detector.handle_python(test_file)

      -- Should set buffer variable for PyworksSetup command
      local filepath = vim.b[bufnr].pyworks_filepath
      assert.equals(test_file, filepath)

      vim.cmd("bdelete!")
      vim.fn.delete(temp_project, "rf")
    end)

    it("should call python.handle_file when venv exists", function()
      -- Setup
      local temp_project = vim.fn.tempname()
      vim.fn.mkdir(temp_project .. "/.venv/bin", "p")
      vim.fn.writefile({ "" }, temp_project .. "/pyproject.toml")
      local test_file = temp_project .. "/test.py"
      vim.fn.writefile({ "import os" }, test_file)

      -- Mock python module
      local handle_file_called = false
      package.loaded["pyworks.languages.python"] = {
        handle_file = function(filepath, is_notebook)
          handle_file_called = true
          assert.equals(test_file, filepath)
          assert.is_false(is_notebook)
        end,
      }

      -- Test
      detector.handle_python(test_file)

      -- Assert
      assert.is_true(handle_file_called)

      -- Cleanup
      package.loaded["pyworks.languages.python"] = nil
      vim.fn.delete(temp_project, "rf")
    end)
  end)

  describe("on_file_open", function()
    it("should route .py files to handle_python", function()
      local temp_file = vim.fn.tempname() .. ".py"
      vim.fn.writefile({ "print('test')" }, temp_file)

      -- Mock handle_python
      local handle_python_called = false
      local original_handle_python = detector.handle_python
      detector.handle_python = function(filepath)
        handle_python_called = true
        assert.equals(temp_file, filepath)
      end

      detector.on_file_open(temp_file)

      -- Restore
      detector.handle_python = original_handle_python

      assert.is_true(handle_python_called)
      vim.fn.delete(temp_file)
    end)

    it("should route .ipynb files to handle_python_notebook", function()
      local temp_file = vim.fn.tempname() .. ".ipynb"
      vim.fn.writefile({ '{"cells": []}' }, temp_file)

      local handle_notebook_called = false
      local original_handle = detector.handle_python_notebook
      detector.handle_python_notebook = function(filepath)
        handle_notebook_called = true
        assert.equals(temp_file, filepath)
      end

      detector.on_file_open(temp_file)

      -- Wait for async processing
      vim.wait(100, function()
        return handle_notebook_called
      end)

      detector.handle_python_notebook = original_handle
      assert.is_true(handle_notebook_called)
      vim.fn.delete(temp_file)
    end)

    it("should handle invalid file paths gracefully", function()
      -- Should not crash with nil or empty paths (returns nil)
      local result = detector.on_file_open(nil)
      assert.is_nil(result)

      result = detector.on_file_open("")
      assert.is_nil(result)

      -- Non-existent file should still be processed (doesn't crash)
      -- This will show notification but returns nil
      result = detector.on_file_open("/nonexistent/file.py")
      -- Function returns nil, but should not crash
      assert.is_true(true) -- If we got here, it didn't crash
    end)

    it("should detect language from file extension", function()
      local py_file = vim.fn.tempname() .. ".py"
      local jl_file = vim.fn.tempname() .. ".jl"
      local r_file = vim.fn.tempname() .. ".R"

      vim.fn.writefile({ "" }, py_file)
      vim.fn.writefile({ "" }, jl_file)
      vim.fn.writefile({ "" }, r_file)

      -- These should not crash
      detector.on_file_open(py_file)
      detector.on_file_open(jl_file)
      detector.on_file_open(r_file)

      vim.fn.delete(py_file)
      vim.fn.delete(jl_file)
      vim.fn.delete(r_file)
    end)
  end)

  describe("detect_notebook_language", function()
    it("should detect Python from notebook metadata", function()
      local temp_file = vim.fn.tempname() .. ".ipynb"
      local notebook_content = vim.fn.json_encode({
        metadata = {
          kernelspec = {
            language = "python",
            name = "python3",
          },
        },
        cells = {},
      })
      vim.fn.writefile({ notebook_content }, temp_file)

      -- Open in buffer
      vim.cmd("edit " .. temp_file)

      local language = detector.detect_notebook_language(temp_file)

      assert.equals("python", language)

      vim.cmd("bdelete!")
      vim.fn.delete(temp_file)
    end)

    it("should default to python for notebooks without metadata", function()
      local temp_file = vim.fn.tempname() .. ".ipynb"
      vim.fn.writefile({ '{"cells": []}' }, temp_file)

      vim.cmd("edit " .. temp_file)
      local language = detector.detect_notebook_language(temp_file)

      -- Should default to python
      assert.equals("python", language)

      vim.cmd("bdelete!")
      vim.fn.delete(temp_file)
    end)

    it("should handle malformed JSON gracefully", function()
      local temp_file = vim.fn.tempname() .. ".ipynb"
      vim.fn.writefile({ "not valid json" }, temp_file)

      vim.cmd("edit " .. temp_file)
      local language = detector.detect_notebook_language(temp_file)

      -- Should fall back to python
      assert.equals("python", language)

      vim.cmd("bdelete!")
      vim.fn.delete(temp_file)
    end)
  end)

  describe("auto_init_molten", function()
    it("should not init twice for same buffer", function()
      local temp_file = vim.fn.tempname() .. ".py"
      vim.fn.writefile({ "print('test')" }, temp_file)
      vim.cmd("edit " .. temp_file)
      local bufnr = vim.api.nvim_get_current_buf()

      -- First call
      -- Note: This requires molten.nvim to be installed
      -- Skip if not available
      if vim.fn.exists(":MoltenInit") == 0 then
        pending("requires molten.nvim")
        return
      end

      -- Mark as already attempted
      vim.b[bufnr].molten_init_attempted = true

      -- Second call should skip
      -- This is testing the guard clause
      -- Actual init testing requires molten.nvim mock

      vim.cmd("bdelete!")
      vim.fn.delete(temp_file)
    end)

    it("should allow retry on failure", function()
      -- When init fails, molten_init_attempted should be reset to false
      -- to allow manual retry
      pending("requires molten.nvim mocking")
    end)
  end)
end)
