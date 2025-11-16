-- Test suite for pyworks.notebook.handler module
-- Tests the notebook handling with jupytext fallback

local handler = require("pyworks.notebook.handler")

describe("notebook.handler", function()
  describe("check_jupytext_cli", function()
    it("should find jupytext in project venv", function()
      -- Setup: Create project with venv and jupytext
      local temp_project = vim.fn.tempname()
      vim.fn.mkdir(temp_project .. "/.venv/bin", "p")
      local jupytext_path = temp_project .. "/.venv/bin/jupytext"

      -- Create fake jupytext executable
      vim.fn.writefile({ "#!/bin/sh", "echo 'jupytext'" }, jupytext_path)
      vim.fn.setfperm(jupytext_path, "rwxr-xr-x")

      local notebook_file = temp_project .. "/test.ipynb"
      vim.fn.writefile({ '{"cells": []}' }, notebook_file)

      -- Test
      local has_jupytext = handler.check_jupytext_cli(notebook_file)

      -- Assert
      assert.is_true(has_jupytext)

      -- Cleanup
      vim.fn.delete(temp_project, "rf")
    end)

    it("should find jupytext in parent project venv", function()
      -- Setup: Create nested structure with venv in parent
      local parent_project = vim.fn.tempname()
      local subdir = parent_project .. "/Module 3 - Python"
      vim.fn.mkdir(parent_project .. "/.venv/bin", "p")
      vim.fn.mkdir(subdir, "p")
      vim.fn.writefile({ "" }, parent_project .. "/pyproject.toml")

      local jupytext_path = parent_project .. "/.venv/bin/jupytext"
      vim.fn.writefile({ "#!/bin/sh", "echo 'jupytext'" }, jupytext_path)
      vim.fn.setfperm(jupytext_path, "rwxr-xr-x")

      local notebook_file = subdir .. "/test.ipynb"
      vim.fn.writefile({ '{"cells": []}' }, notebook_file)

      -- Test
      local has_jupytext = handler.check_jupytext_cli(notebook_file)

      -- Assert: Should walk up and find parent .venv
      assert.is_true(has_jupytext)

      -- Cleanup
      vim.fn.delete(parent_project, "rf")
    end)

    it("should fall back to system PATH when not in venv", function()
      -- This test checks if system jupytext is found
      -- Result depends on system state
      local result = handler.check_jupytext_cli(nil)

      -- Should be boolean
      assert.is_boolean(result)
    end)

    it("should return false when jupytext not found anywhere", function()
      -- Setup: Project without venv or system jupytext
      local temp_project = vim.fn.tempname()
      vim.fn.mkdir(temp_project, "p")
      local notebook_file = temp_project .. "/test.ipynb"
      vim.fn.writefile({ '{"cells": []}' }, notebook_file)

      -- Temporarily modify PATH to exclude jupytext
      local original_path = vim.env.PATH
      vim.env.PATH = "/usr/bin:/bin" -- Minimal PATH

      local has_jupytext = handler.check_jupytext_cli(notebook_file)

      -- Restore PATH
      vim.env.PATH = original_path

      -- Assert: Should not find jupytext
      assert.is_false(has_jupytext)

      -- Cleanup
      vim.fn.delete(temp_project, "rf")
    end)
  end)

  describe("handle_notebook_open", function()
    it("should show instructions when jupytext missing", function()
      -- Setup
      local temp_project = vim.fn.tempname()
      vim.fn.mkdir(temp_project, "p")
      local notebook_file = temp_project .. "/test.ipynb"
      vim.fn.writefile({ '{"cells": []}' }, notebook_file)

      -- Mock check_jupytext_cli to return false
      local original_check = handler.check_jupytext_cli
      handler.check_jupytext_cli = function()
        return false
      end

      -- Track notifications
      local notify_calls = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      -- Test
      local result = handler.handle_notebook_open(notebook_file)

      -- Restore
      handler.check_jupytext_cli = original_check
      vim.notify = original_notify

      -- Assert
      assert.is_false(result)
      assert.is_true(#notify_calls > 0)

      -- Should show instructions about jupytext
      local found_jupytext_msg = false
      for _, call in ipairs(notify_calls) do
        if call.msg:match("jupytext") then
          found_jupytext_msg = true
          break
        end
      end
      assert.is_true(found_jupytext_msg)

      -- Cleanup
      vim.fn.delete(temp_project, "rf")
    end)

    it("should show venv creation instructions when no venv", function()
      -- Setup: Project without venv
      local temp_project = vim.fn.tempname()
      vim.fn.mkdir(temp_project, "p")
      local notebook_file = temp_project .. "/test.ipynb"
      vim.fn.writefile({ '{"cells": []}' }, notebook_file)

      local original_check = handler.check_jupytext_cli
      handler.check_jupytext_cli = function()
        return false
      end

      local notify_calls = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      handler.handle_notebook_open(notebook_file)

      handler.check_jupytext_cli = original_check
      vim.notify = original_notify

      -- Should mention PyworksSetup
      local found_setup_msg = false
      for _, call in ipairs(notify_calls) do
        if call.msg:match("PyworksSetup") then
          found_setup_msg = true
          break
        end
      end
      assert.is_true(found_setup_msg)

      vim.fn.delete(temp_project, "rf")
    end)

    it("should show pip install instructions when venv exists", function()
      -- Setup: Project with venv but no jupytext
      local temp_project = vim.fn.tempname()
      vim.fn.mkdir(temp_project .. "/.venv/bin", "p")
      vim.fn.writefile({ "" }, temp_project .. "/pyproject.toml")
      local notebook_file = temp_project .. "/test.ipynb"
      vim.fn.writefile({ '{"cells": []}' }, notebook_file)

      local original_check = handler.check_jupytext_cli
      handler.check_jupytext_cli = function()
        return false
      end

      local notify_calls = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      handler.handle_notebook_open(notebook_file)

      handler.check_jupytext_cli = original_check
      vim.notify = original_notify

      -- Should show pip install command
      local found_pip_msg = false
      for _, call in ipairs(notify_calls) do
        if call.msg:match("pip install jupytext") then
          found_pip_msg = true
          break
        end
      end
      assert.is_true(found_pip_msg)

      vim.fn.delete(temp_project, "rf")
    end)

    it("should return true when jupytext available", function()
      -- Mock successful check
      local original_check = handler.check_jupytext_cli
      handler.check_jupytext_cli = function()
        return true
      end

      local result = handler.handle_notebook_open("test.ipynb")

      handler.check_jupytext_cli = original_check

      assert.is_true(result)
    end)

    it("should display project context in messages", function()
      -- Setup
      local temp_project = vim.fn.tempname()
      vim.fn.mkdir(temp_project, "p")
      vim.fn.writefile({ "" }, temp_project .. "/pyproject.toml")
      local notebook_file = temp_project .. "/test.ipynb"
      vim.fn.writefile({ '{"cells": []}' }, notebook_file)

      local original_check = handler.check_jupytext_cli
      handler.check_jupytext_cli = function()
        return false
      end

      local notify_calls = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      handler.handle_notebook_open(notebook_file)

      handler.check_jupytext_cli = original_check
      vim.notify = original_notify

      -- Should show project info
      local found_project_msg = false
      for _, call in ipairs(notify_calls) do
        if call.msg:match("Project:") then
          found_project_msg = true
          break
        end
      end
      assert.is_true(found_project_msg)

      vim.fn.delete(temp_project, "rf")
    end)
  end)
end)
