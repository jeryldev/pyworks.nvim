-- Example setup for LazyVim users
-- Place this in ~/.config/nvim/lua/plugins/pyworks-setup.lua

return {
  {
    -- Using local development version for testing
    dir = "~/PycharmProjects/iron_training/pyworks.nvim",
    -- "jeryldev/pyworks.nvim",  -- GitHub version (uncomment for production)
    dependencies = {
      {
        "GCBallesteros/jupytext.nvim",
        config = true, -- This ensures jupytext.setup() is called!
      },
      "nvim-lua/plenary.nvim", -- Required: Core utilities
      "benlubas/molten-nvim", -- Required: Code execution
      "3rd/image.nvim", -- Required: Image display
    },
    config = function()
      require("pyworks").setup({
        -- Pyworks auto-configures everything with proven settings!
        -- Just specify any preferences:
        python = {
          use_uv = true, -- Use uv for faster package installation
        },
        image_backend = "kitty", -- or "ueberzug" for X11

        -- Optional: Skip auto-configuration of specific dependencies
        -- skip_molten = false,
        -- skip_jupytext = false,
        -- skip_image = false,
        -- skip_keymaps = false,
      })
    end,
    lazy = false, -- Load immediately for file detection
    priority = 100, -- Load early
  },
}