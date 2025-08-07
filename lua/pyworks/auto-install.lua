-- Auto-install dependencies for pyworks.nvim
local M = {}
local utils = require("pyworks.utils")

-- Get the appropriate plugin directory based on the package manager
function M.get_plugin_dir()
	-- Check common plugin directories
	local dirs = {
		vim.fn.stdpath("data") .. "/lazy",  -- lazy.nvim
		vim.fn.stdpath("data") .. "/site/pack/packer/start",  -- packer
		vim.fn.stdpath("data") .. "/plugged",  -- vim-plug
		vim.fn.stdpath("data") .. "/bundle",  -- Vundle/Pathogen
	}
	
	-- Find the first existing directory
	for _, dir in ipairs(dirs) do
		if vim.fn.isdirectory(dir) == 1 then
			return dir
		end
	end
	
	-- Default to lazy.nvim location
	local default_dir = vim.fn.stdpath("data") .. "/lazy"
	vim.fn.mkdir(default_dir, "p")
	return default_dir
end

-- Check if a plugin is installed
function M.is_plugin_installed(name)
	local plugin_dir = M.get_plugin_dir()
	local plugin_path = plugin_dir .. "/" .. name
	return vim.fn.isdirectory(plugin_path) == 1
end

-- Clone a git repository
function M.clone_plugin(repo_url, name)
	local plugin_dir = M.get_plugin_dir()
	local plugin_path = plugin_dir .. "/" .. name
	
	if vim.fn.isdirectory(plugin_path) == 1 then
		return true, "Already installed"
	end
	
	utils.notify("Installing " .. name .. "...", vim.log.levels.INFO)
	
	local cmd = string.format("git clone --depth 1 %s %s", repo_url, plugin_path)
	local result = vim.fn.system(cmd)
	
	if vim.v.shell_error == 0 then
		return true, "Successfully installed"
	else
		return false, "Failed to install: " .. result
	end
end

-- Install Molten
function M.install_molten()
	if vim.fn.exists(":MoltenInit") == 2 then
		return true, "Molten already available"
	end
	
	-- Clone molten-nvim
	local success, msg = M.clone_plugin("https://github.com/benlubas/molten-nvim", "molten-nvim")
	if not success then
		return false, msg
	end
	
	-- Add to runtimepath
	local plugin_path = M.get_plugin_dir() .. "/molten-nvim"
	vim.opt.runtimepath:append(plugin_path)
	
	-- Configure Molten (matching your config exactly)
	vim.g.molten_image_provider = "image.nvim"
	vim.g.molten_output_win_max_height = 40  -- Increased for larger images
	vim.g.molten_output_win_max_width = 150  -- Allow wider output windows
	vim.g.molten_auto_open_output = true     -- Auto-show output after execution
	vim.g.molten_output_crop_border = true   -- Crop border at screen edge
	
	-- Run UpdateRemotePlugins
	utils.notify("Setting up Molten remote plugins...", vim.log.levels.INFO)
	local ok = pcall(vim.cmd, "UpdateRemotePlugins")
	if not ok then
		utils.notify("Failed to update remote plugins - manual setup required", vim.log.levels.WARN)
		utils.notify("Run :UpdateRemotePlugins manually, then restart Neovim", vim.log.levels.INFO)
	end
	
	-- Mark that we need a restart
	vim.g.pyworks_needs_restart = true
	
	return true, "Molten installed - restart Neovim to complete setup"
end

-- Install image.nvim
function M.install_image_nvim()
	local ok = pcall(require, "image")
	if ok then
		return true, "image.nvim already available"
	end
	
	-- Clone image.nvim
	local success, msg = M.clone_plugin("https://github.com/3rd/image.nvim", "image.nvim")
	if not success then
		return false, msg
	end
	
	-- Add to runtimepath
	local plugin_path = M.get_plugin_dir() .. "/image.nvim"
	vim.opt.runtimepath:append(plugin_path)
	
	-- Try to load and configure (matching your config exactly)
	local ok, image = pcall(require, "image")
	if ok then
		image.setup({
			backend = "kitty",
			integrations = {},  -- Empty for Molten
			max_width = 150,  -- Increased for larger images
			max_height = 40,  -- Match Molten's max height
			max_height_window_percentage = math.huge,
			max_width_window_percentage = math.huge,
			window_overlap_clear_enabled = true,
			window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
		})
		return true, "image.nvim installed and configured"
	else
		return true, "image.nvim installed - restart Neovim to activate"
	end
end

-- Install jupytext.nvim
function M.install_jupytext()
	local ok = pcall(require, "jupytext")
	if ok then
		return true, "jupytext.nvim already available"
	end
	
	-- Clone jupytext.nvim
	local success, msg = M.clone_plugin("https://github.com/GCBallesteros/jupytext.nvim", "jupytext.nvim")
	if not success then
		return false, msg
	end
	
	-- Add to runtimepath
	local plugin_path = M.get_plugin_dir() .. "/jupytext.nvim"
	vim.opt.runtimepath:append(plugin_path)
	
	-- Try to load and configure
	local ok, jupytext = pcall(require, "jupytext")
	if ok then
		jupytext.setup({
			style = "percent",
			output_extension = "auto",
			force_ft = nil,
			custom_language_formatting = {},
		})
		return true, "jupytext.nvim installed and configured"
	else
		return true, "jupytext.nvim installed - restart Neovim to activate"
	end
end

-- Auto-install all dependencies
function M.auto_install_all()
	local needs_restart = false
	
	-- Check and install jupytext.nvim
	if not pcall(require, "jupytext") then
		utils.notify("Installing jupytext.nvim for notebook support...", vim.log.levels.INFO)
		local success, msg = M.install_jupytext()
		if success then
			utils.notify("✓ " .. msg, vim.log.levels.INFO)
			if msg:match("restart") then needs_restart = true end
		else
			utils.notify("✗ " .. msg, vim.log.levels.ERROR)
		end
	end
	
	-- Check and install Molten
	if vim.fn.exists(":MoltenInit") ~= 2 then
		utils.notify("Installing molten-nvim for Jupyter kernel support...", vim.log.levels.INFO)
		local success, msg = M.install_molten()
		if success then
			utils.notify("✓ " .. msg, vim.log.levels.INFO)
			if msg:match("restart") then needs_restart = true end
		else
			utils.notify("✗ " .. msg, vim.log.levels.ERROR)
		end
	end
	
	-- Check and install image.nvim
	if not pcall(require, "image") then
		-- Only install if using supported terminal
		local term = vim.env.TERM or ""
		local kitty_id = vim.env.KITTY_WINDOW_ID
		if kitty_id or term:match("kitty") or term:match("ghostty") then
			utils.notify("Installing image.nvim for plot display...", vim.log.levels.INFO)
			local success, msg = M.install_image_nvim()
			if success then
				utils.notify("✓ " .. msg, vim.log.levels.INFO)
				if msg:match("restart") then needs_restart = true end
			else
				utils.notify("✗ " .. msg, vim.log.levels.ERROR)
			end
		end
	end
	
	if needs_restart then
		utils.notify("", vim.log.levels.INFO)
		utils.notify("=====================================", vim.log.levels.WARN)
		utils.notify("Please restart Neovim to complete setup", vim.log.levels.WARN)
		utils.notify("=====================================", vim.log.levels.WARN)
	end
	
	return not needs_restart
end

-- Check and offer to install missing dependencies
function M.check_and_prompt()
	local missing = {}
	
	if vim.fn.exists(":MoltenInit") ~= 2 then
		table.insert(missing, "molten-nvim (Jupyter kernel support)")
	end
	
	if not pcall(require, "jupytext") then
		table.insert(missing, "jupytext.nvim (notebook file support)")
	end
	
	if not pcall(require, "image") then
		local term = vim.env.TERM or ""
		local kitty_id = vim.env.KITTY_WINDOW_ID
		if kitty_id or term:match("kitty") or term:match("ghostty") then
			table.insert(missing, "image.nvim (plot display)")
		end
	end
	
	if #missing > 0 then
		utils.notify("Missing optional dependencies:", vim.log.levels.INFO)
		for _, dep in ipairs(missing) do
			utils.notify("  • " .. dep, vim.log.levels.INFO)
		end
		
		utils.better_select("Install missing dependencies?", {"Yes - Install now", "No - Skip"}, function(choice)
			if choice == "Yes - Install now" then
				M.auto_install_all()
			end
		end)
	end
end

return M