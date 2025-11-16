-- Keymaps for pyworks.nvim
-- Cell execution with Molten integration for ALL 6 scenarios:
-- 1. Python files (.py) with python3 kernel
-- 2. Julia files (.jl) with julia kernel
-- 3. R files (.R) with ir kernel
-- 4. Python notebooks (.ipynb) with python3 kernel
-- 5. Julia notebooks (.ipynb) with julia kernel
-- 6. R notebooks (.ipynb) with ir kernel
-- ALL use Molten + image.nvim for execution and display

local M = {}

local error_handler = require("pyworks.core.error_handler")

-- Set up keymaps for a buffer
function M.setup_buffer_keymaps()
  local opts = { buffer = true, silent = true }

  -- Check if Molten is available (it's a remote plugin, not a Lua module)
  local has_molten = vim.fn.exists(":MoltenInit") == 2

  if has_molten then
    -- Molten-specific keymaps

    -- Run current line
    vim.keymap.set("n", "<leader>jl", function()
      -- Check if kernel is initialized for this buffer
      local bufnr = vim.api.nvim_get_current_buf()
      if not vim.b[bufnr].molten_initialized then
        -- Auto-initialize based on file type
        local ft = vim.bo.filetype
        local filepath = vim.api.nvim_buf_get_name(bufnr)
        local detector = require("pyworks.core.detector")
        -- Pass filepath for project-aware kernel selection
        local kernel = detector.get_kernel_for_language(ft, filepath)

        if kernel then
          vim.notify("Initializing " .. kernel .. " kernel...", vim.log.levels.INFO)
          local ok = error_handler.protected_call(vim.cmd, "Failed to initialize kernel", "MoltenInit " .. kernel)
          if ok then
            vim.b[bufnr].molten_initialized = true
          end

          -- Wait a moment then run the line
          vim.defer_fn(function()
            error_handler.protected_call(vim.cmd, "Failed to evaluate line", "MoltenEvaluateLine")
            -- Move to next line
            local cursor = vim.api.nvim_win_get_cursor(0)
            local next_line = cursor[1] + 1
            local last_line = vim.api.nvim_buf_line_count(0)
            if next_line <= last_line then
              vim.api.nvim_win_set_cursor(0, { next_line, cursor[2] })
            end
          end, 100)
          return
        end
      end

      -- Kernel should be initialized, run the line
      vim.cmd("MoltenEvaluateLine")

      -- Move to next line for convenience
      local cursor = vim.api.nvim_win_get_cursor(0)
      local next_line = cursor[1] + 1
      local last_line = vim.api.nvim_buf_line_count(0)
      if next_line <= last_line then
        vim.api.nvim_win_set_cursor(0, { next_line, cursor[2] })
      end
    end, vim.tbl_extend("force", opts, { desc = "Molten: Run current line" }))

    -- Run visual selection
    vim.keymap.set(
      "v",
      "<leader>jr",
      ":<C-u>MoltenEvaluateVisual<CR>",
      vim.tbl_extend("force", opts, { desc = "Run selection" })
    )

    -- Also support visual block mode
    vim.keymap.set(
      "x",
      "<leader>jr",
      ":<C-u>MoltenEvaluateVisual<CR>",
      vim.tbl_extend("force", opts, { desc = "Run selection" })
    )

    -- Select/highlight current cell (between cell markers) or entire file
    vim.keymap.set("n", "<leader>jc", function()
      -- Check if Python provider is working
      if vim.bo.filetype == "python" and not vim.g.python3_host_prog then
        vim.notify("⚠️  Python host not configured. Run :PyworksSetup first", vim.log.levels.WARN)
        return
      end

      -- Save current position
      local save_cursor = vim.api.nvim_win_get_cursor(0)

      -- Check if there are any cell markers in the file
      local has_cells = vim.fn.search("^# %%", "nw") > 0

      if has_cells then
        -- Find and select the current cell
        local cell_start = vim.fn.search("^# %%", "bnW") -- Search backwards
        if cell_start == 0 then
          -- We're before the first cell, select from beginning
          vim.cmd("normal! gg")
        else
          vim.cmd("normal! " .. cell_start .. "G")
          vim.cmd("normal! j") -- Move past the cell marker
        end

        vim.cmd("normal! V")                      -- Start visual line mode

        local cell_end = vim.fn.search("^# %%", "nW") -- Search forwards
        if cell_end == 0 then
          -- We're in the last cell, select to end
          vim.cmd("normal! G")
        else
          vim.cmd("normal! " .. cell_end .. "G")
          vim.cmd("normal! k") -- Don't include the next cell marker
        end
      else
        -- No cell markers, select the entire file
        vim.cmd("normal! ggVG")
        vim.notify("No cell markers found, selected entire file", vim.log.levels.INFO)
      end
    end, vim.tbl_extend("force", opts, { desc = "Select current cell" }))


    -- Hover to show output (using K or gh)
    vim.keymap.set("n", "K", function()
      -- Check if we're on a cell that has output
      local ok, _ = pcall(vim.cmd, "MoltenShowOutput")
      if not ok then
        -- Fall back to default K behavior (show hover docs)
        vim.lsp.buf.hover()
      end
    end, vim.tbl_extend("force", opts, { desc = "Show Molten output or LSP hover" }))
  else
    -- Fallback keymaps when Molten is not available
    -- These just select text for manual copying

    vim.keymap.set("n", "<leader>jc", function()
      -- Highlight/select current cell
      vim.cmd("normal! ?^# %%\\|^```\\|^```{<CR>") -- Go to cell start
      vim.cmd("normal! V")                      -- Start visual line mode
      vim.cmd("normal! /^# %%\\|^```\\|^```{<CR>") -- Go to next cell start
      vim.cmd("normal! k")                      -- Go up one line to exclude next cell marker
      vim.notify("Molten not available. Cell selected for manual copy.", vim.log.levels.WARN)
    end, vim.tbl_extend("force", opts, { desc = "Select current cell (Molten not available)" }))

    vim.keymap.set("v", "<leader>jr", function()
      vim.notify("Molten not available. Copy selection to run elsewhere.", vim.log.levels.WARN)
    end, vim.tbl_extend("force", opts, { desc = "Run selection (Molten not available)" }))

    vim.keymap.set("n", "<leader>jl", function()
      vim.notify("Molten not available. Use :MoltenInit to initialize.", vim.log.levels.WARN)
    end, vim.tbl_extend("force", opts, { desc = "Run current line (Molten not available)" }))
  end

  -- Cell navigation (works with or without Molten)
  vim.keymap.set("n", "<leader>j]", function()
    -- Search for next cell marker (# %% for Python/Julia/R notebooks)
    local found = vim.fn.search("^# %%", "W")
    if found == 0 then
      vim.notify("No more cells", vim.log.levels.INFO)
    end
  end, vim.tbl_extend("force", opts, { desc = "Next cell" }))

  vim.keymap.set("n", "<leader>j[", function()
    -- Search for previous cell marker
    local found = vim.fn.search("^# %%", "bW")
    if found == 0 then
      vim.notify("No previous cells", vim.log.levels.INFO)
    end
  end, vim.tbl_extend("force", opts, { desc = "Previous cell" }))
end

-- Set up Molten kernel management keymaps
function M.setup_molten_keymaps()
  local opts = { buffer = true, silent = true }

  -- Check if Molten is available (it's a remote plugin, not a Lua module)
  local has_molten = vim.fn.exists(":MoltenInit") == 2

  if has_molten then
    -- Restart kernel (when things go wrong)
    vim.keymap.set("n", "<leader>mr", function()
      vim.cmd("MoltenRestart")
    end, vim.tbl_extend("force", opts, { desc = "Restart kernel" }))

    -- Interrupt execution (stop long-running code)
    vim.keymap.set("n", "<leader>mx", function()
      vim.cmd("MoltenInterrupt")
    end, vim.tbl_extend("force", opts, { desc = "Interrupt execution" }))
  end
end

return M
