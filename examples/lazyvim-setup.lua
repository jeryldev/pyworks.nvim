-- Example setup for LazyVim users
-- Place this in ~/.config/nvim/lua/plugins/pyworks-setup.lua
-- Dependencies (jeryldev/molten-nvim, jeryldev/image.nvim) are installed automatically via lazy.lua

return {
  {
    "jeryldev/pyworks.nvim",
    config = function()
      require("pyworks").setup({
        -- Pyworks auto-configures everything with proven settings!
        -- Just specify any preferences:
        python = {
          use_uv = true,     -- Use uv for faster package installation
        },
        image_backend = "kitty", -- or "ueberzug" for X11

        -- Optional: Skip auto-configuration of specific dependencies
        -- skip_molten = false,
        -- skip_jupytext = false,  -- Set true if using jupytext.nvim plugin instead
        -- skip_image = false,
        -- skip_keymaps = false,
      })
    end,
    lazy = false,
  },
}
