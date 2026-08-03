-- Minimal config: molten + pyworks, nothing else
vim.opt.runtimepath:append("/opt/molten-nvim")
vim.opt.runtimepath:append("/opt/image.nvim")
vim.opt.runtimepath:append("/work/pyworks")
package.path = "/work/pyworks/lua/?.lua;/work/pyworks/lua/?/init.lua;" .. package.path

vim.g.python3_host_prog = "/work/project/.venv/bin/python"
vim.g.molten_virt_text_output = true
vim.g.molten_auto_open_output = false
vim.g.molten_tick_rate = 100

-- pyworks configures the .ipynb read handler during setup; without this the
-- notebook opens as raw JSON
require("pyworks").setup()
