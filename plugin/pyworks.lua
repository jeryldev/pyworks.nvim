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
