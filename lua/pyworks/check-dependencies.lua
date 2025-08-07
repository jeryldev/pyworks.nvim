-- Check and report on pyworks dependencies
local M = {}
local utils = require("pyworks.utils")

function M.check_molten()
	-- Check if Molten is available
	if vim.fn.exists(":MoltenInit") == 2 then
		return true, "Molten is installed and available"
	else
		return false, "Molten not found - needed for Jupyter kernel support"
	end
end

function M.check_jupytext()
	-- Check if jupytext.nvim is available
	local ok = pcall(require, "jupytext")
	if ok then
		return true, "jupytext.nvim is installed"
	else
		return false, "jupytext.nvim not found - needed for .ipynb file support"
	end
end

function M.check_image()
	-- Check if image.nvim is available
	local ok = pcall(require, "image")
	if ok then
		return true, "image.nvim is installed"
	else
		return false, "image.nvim not found - needed for inline plot display"
	end
end

function M.check_all()
	utils.notify("=== Pyworks Dependency Check ===", vim.log.levels.INFO)
	
	local molten_ok, molten_msg = M.check_molten()
	local jupytext_ok, jupytext_msg = M.check_jupytext()
	local image_ok, image_msg = M.check_image()
	
	-- Report status
	if molten_ok then
		utils.notify("✓ " .. molten_msg, vim.log.levels.INFO)
	else
		utils.notify("✗ " .. molten_msg, vim.log.levels.WARN)
	end
	
	if jupytext_ok then
		utils.notify("✓ " .. jupytext_msg, vim.log.levels.INFO)
	else
		utils.notify("✗ " .. jupytext_msg, vim.log.levels.WARN)
	end
	
	if image_ok then
		utils.notify("✓ " .. image_msg, vim.log.levels.INFO)
	else
		utils.notify("✗ " .. image_msg, vim.log.levels.WARN)
	end
	
	-- Provide guidance if dependencies are missing
	if not (molten_ok and jupytext_ok and image_ok) then
		utils.notify("", vim.log.levels.INFO)
		utils.notify("To install missing dependencies:", vim.log.levels.INFO)
		utils.notify("1. Add them to your plugin manager config (see README)", vim.log.levels.INFO)
		utils.notify("2. Or run :PyworksSetup and choose 'Data Science / Notebooks'", vim.log.levels.INFO)
		utils.notify("", vim.log.levels.INFO)
		utils.notify("Minimal config for lazy.nvim:", vim.log.levels.INFO)
		utils.notify([[{
  "jeryldev/pyworks.nvim",
  dependencies = {
    "GCBallesteros/jupytext.nvim",
    { "benlubas/molten-nvim", build = ":UpdateRemotePlugins" },
    "3rd/image.nvim",
  },
}]], vim.log.levels.INFO)
	else
		utils.notify("", vim.log.levels.INFO)
		utils.notify("✓ All dependencies installed!", vim.log.levels.INFO)
	end
	
	return molten_ok and jupytext_ok and image_ok
end

return M