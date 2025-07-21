-- pyworks.nvim - Plugin loader
-- This file is automatically loaded by Neovim

if vim.g.loaded_pyworks then
  return
end
vim.g.loaded_pyworks = 1

-- Defer actual loading to allow lazy.nvim to handle dependencies
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    -- Only create commands if setup hasn't been called
    -- This prevents duplicate commands when using plugin managers
    if not vim.g.pyworks_setup_complete then
      require("pyworks.commands").create_commands()
    end
  end,
  once = true,
})