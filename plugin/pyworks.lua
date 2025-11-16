-- pyworks.nvim - Plugin loader
-- This file is automatically loaded by Neovim

if vim.g.loaded_pyworks then
  return
end
vim.g.loaded_pyworks = 1

-- Emergency Molten disable via environment variable
if vim.env.PYWORKS_NO_MOLTEN then
  vim.g.molten_error_detected = true
  vim.notify("Molten disabled via PYWORKS_NO_MOLTEN environment variable", vim.log.levels.WARN)
end

-- Create autocmd group for pyworks
local augroup = vim.api.nvim_create_augroup("Pyworks", { clear = true })

-- Helper function to check if a file is in a pyworks-managed directory
local function is_pyworks_project(filepath)
  -- Check for common project markers
  local markers = {
    ".venv",          -- Python virtual environment
    "Project.toml",   -- Julia project
    "renv.lock",      -- R project with renv
    ".Rproj",         -- RStudio project
    "requirements.txt", -- Python requirements
    "setup.py",       -- Python package
    "pyproject.toml", -- Modern Python project
    "Manifest.toml",  -- Julia manifest
  }

  -- Use the file's directory, not cwd!
  local dir = filepath and vim.fn.fnamemodify(filepath, ":h") or vim.fn.getcwd()

  -- Walk up the directory tree to find a project root
  local current = dir
  local last = ""
  while current ~= last do
    for _, marker in ipairs(markers) do
      if
          vim.fn.filereadable(current .. "/" .. marker) == 1
          or vim.fn.isdirectory(current .. "/" .. marker) == 1
      then
        return true
      end
    end
    last = current
    current = vim.fn.fnamemodify(current, ":h")
  end

  return false
end

-- Set up autocmds for file detection
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = augroup,
  pattern = { "*.py", "*.jl", "*.R" }, -- Removed *.ipynb to let jupytext handle it first
  callback = function(ev)
    -- Get the actual buffer number and its full path
    local bufnr = ev.buf
    local full_path = vim.api.nvim_buf_get_name(bufnr)

    -- Use the full path for project detection
    local check_path = full_path ~= "" and full_path or ev.file

    -- For Python files, ALWAYS run pyworks (it will create venv if needed)
    -- For other languages, check for project markers
    local ext = vim.fn.fnamemodify(check_path, ":e")
    local ft = vim.bo[bufnr].filetype

    -- Always process Python files and notebooks
    if ext ~= "py" and ext ~= "ipynb" and ft ~= "python" then
      -- For non-Python files, check for project markers
      if not is_pyworks_project(check_path) then
        return
      end
    end

    -- Debug: Show that autocmd fired
    if vim.g.pyworks_debug then
      vim.notify("[Pyworks] File opened: " .. check_path, vim.log.levels.DEBUG)
    end

    -- Use defer_fn for non-blocking operation
    vim.defer_fn(function()
      local detector = require("pyworks.core.detector")
      -- Use the full path directly
      detector.on_file_open(full_path)
    end, 100) -- Small delay to let buffer settle
  end,
  desc = "Pyworks: Detect and handle file type",
})

-- Re-scan on save for new imports
vim.api.nvim_create_autocmd("BufWritePost", {
  group = augroup,
  pattern = { "*.py", "*.jl", "*.R", "*.ipynb" },
  callback = function(ev)
    -- Only run in project directories (check the file's location)
    if not is_pyworks_project(ev.file) then
      return
    end

    vim.defer_fn(function()
      local detector = require("pyworks.core.detector")
      detector.rescan_imports(ev.file)
    end, 100)
  end,
  desc = "Pyworks: Re-scan imports after save",
})

-- Set up keymaps for package installation and cell execution
vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = { "python", "julia", "r" },
  callback = function(ev)
    -- Only set up keymaps in project directories (check the file's location)
    local filepath = vim.api.nvim_buf_get_name(ev.buf)
    if not is_pyworks_project(filepath) then
      -- Still set up Molten keymaps even outside projects
      local keymaps = require("pyworks.keymaps")
      keymaps.setup_buffer_keymaps()
      keymaps.setup_molten_keymaps()
      return
    end

    -- Package installation keymap
    vim.keymap.set("n", "<leader>pi", function()
      local ft = vim.bo.filetype
      if ft == "python" then
        local python = require("pyworks.languages.python")
        python.install_missing_packages()
      elseif ft == "julia" then
        local julia = require("pyworks.languages.julia")
        julia.install_missing_packages()
      elseif ft == "r" then
        local r = require("pyworks.languages.r")
        r.install_missing_packages()
      end
    end, { buffer = true, desc = "Pyworks: Install missing packages" })

    -- Set up cell execution keymaps for Molten
    local keymaps = require("pyworks.keymaps")
    keymaps.setup_buffer_keymaps()
    keymaps.setup_molten_keymaps()

    -- For notebooks (.ipynb files converted by jupytext), trigger auto-initialization
    -- This is needed because jupytext changes the filetype after conversion
    local filepath = vim.api.nvim_buf_get_name(ev.buf)
    if filepath:match("%.ipynb$") then
      -- Check if jupytext successfully converted the file
      local first_line = vim.api.nvim_buf_get_lines(ev.buf, 0, 1, false)[1] or ""
      if first_line:match("^{") then
        -- It's still JSON, jupytext didn't work
        local utils = require("pyworks.utils")
        local project_dir, venv_path = utils.get_project_paths(filepath)
        local project_type = utils.detect_project_type(project_dir)
        local project_rel = vim.fn.fnamemodify(project_dir, ":~:.")

        vim.notify(
          string.format("❌ %s notebook not converted: jupytext missing", project_type),
          vim.log.levels.ERROR
        )
        vim.notify(
          string.format("💡 Run :PyworksSetup to create venv at: %s/.venv", project_rel),
          vim.log.levels.INFO
        )
        return
      end

      -- Jupytext worked, handle the notebook
      vim.defer_fn(function()
        local detector = require("pyworks.core.detector")
        -- Trigger auto-initialization based on the filetype
        local ft = vim.bo[ev.buf].filetype
        if ft == "python" then
          detector.handle_python_notebook(filepath)
        elseif ft == "julia" then
          detector.handle_julia_notebook(filepath)
        elseif ft == "r" then
          detector.handle_r_notebook(filepath)
        end
      end, 200) -- Delay to ensure everything is ready
    end
  end,
  desc = "Pyworks: Set up language-specific keymaps and auto-init for notebooks",
})

-- Clean up cache periodically
vim.api.nvim_create_autocmd("VimEnter", {
  group = augroup,
  callback = function()
    vim.defer_fn(function()
      local cache = require("pyworks.core.cache")
      cache.start_periodic_cleanup(300) -- Every 5 minutes
    end, 5000)
  end,
  desc = "Pyworks: Start cache cleanup timer",
})
