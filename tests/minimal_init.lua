-- Minimal init for testing
-- Sets up the necessary paths and loads pyworks.nvim for testing

-- Add parent directory to package path
local pyworks_path = vim.fn.fnamemodify(vim.fn.getcwd(), ":h")
package.path = package.path .. ";" .. pyworks_path .. "/lua/?.lua"
package.path = package.path .. ";" .. pyworks_path .. "/lua/?/init.lua"

-- Add plenary to runtimepath if available
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
	vim.opt.runtimepath:append(plenary_path)
end

-- Disable unnecessary features for testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Set up minimal environment
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

-- Ensure temp directory exists
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, "p")
vim.env.TMPDIR = temp_dir

print("Minimal init loaded for pyworks.nvim tests")
print("Package path: " .. package.path)
