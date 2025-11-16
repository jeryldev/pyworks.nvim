-- Commands for creating new notebook files
local M = {}

-- Helper function to validate filename
local function validate_filename(filename, extension)
	-- Check for invalid characters
	if filename:match("[<>:|?*]") then
		vim.notify("❌ Invalid filename: " .. filename, vim.log.levels.ERROR)
		return nil
	end
	
	-- Ensure correct extension
	if not filename:match("%." .. extension .. "$") then
		filename = filename .. "." .. extension
	end
	
	-- Check if file already exists
	if vim.fn.filereadable(filename) == 1 then
		local choice = vim.fn.confirm(
			"File '" .. filename .. "' already exists. Overwrite?",
			"&Yes\n&No",
			2
		)
		if choice ~= 1 then
			return nil
		end
	end
	
	return filename
end

-- Helper function to create file with template
local function create_file_with_template(filename, template_lines, filetype)
	local ok, err
	
	-- Create or open file
	if filename then
		ok, err = pcall(vim.cmd, "edit " .. filename)
		if not ok then
			vim.notify("❌ Failed to create file: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return false
		end
	else
		ok, err = pcall(vim.cmd, "enew")
		if not ok then
			vim.notify("❌ Failed to create new buffer: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return false
		end
	end
	
	-- Add template content
	ok, err = pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, template_lines)
	if not ok then
		vim.notify("❌ Failed to set template content: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return false
	end
	
	-- Set filetype for syntax highlighting
	vim.bo.filetype = filetype
	
	return true
end

-- Create a new Python file with cell markers
vim.api.nvim_create_user_command("PyworksNewPython", function(opts)
	local filename = opts.args ~= "" and opts.args or nil
	
	-- Validate filename if provided
	if filename then
		filename = validate_filename(filename, "py")
		if not filename then return end
	end
	
	-- Template content
	local template = {
		"# %%",
		"import numpy as np",
		"import pandas as pd",
		"import matplotlib.pyplot as plt",
		"",
		"# %%",
		"# Your code here",
		"",
	}
	
	-- Create file with template
	if create_file_with_template(filename, template, "python") then
		if filename then
			vim.notify("✅ Created Python notebook: " .. filename, vim.log.levels.INFO)
		else
			vim.notify("✅ Created new Python notebook (use :w to save)", vim.log.levels.INFO)
		end
	end
end, { nargs = "?", desc = "Create new Python file with cells" })

-- Create a new Julia file with cell markers
vim.api.nvim_create_user_command("PyworksNewJulia", function(opts)
	local filename = opts.args ~= "" and opts.args or nil
	
	-- Validate filename if provided
	if filename then
		filename = validate_filename(filename, "jl")
		if not filename then return end
	end
	
	-- Template content
	local template = {
		"# %%",
		"using Plots",
		"using DataFrames",
		"using Statistics",
		"",
		"# %%",
		"# Your code here",
		"",
	}
	
	-- Create file with template
	if create_file_with_template(filename, template, "julia") then
		if filename then
			vim.notify("✅ Created Julia notebook: " .. filename, vim.log.levels.INFO)
		else
			vim.notify("✅ Created new Julia notebook (use :w to save)", vim.log.levels.INFO)
		end
	end
end, { nargs = "?", desc = "Create new Julia file with cells" })

-- Create a new R file with cell markers
vim.api.nvim_create_user_command("PyworksNewR", function(opts)
	local filename = opts.args ~= "" and opts.args or nil
	
	-- Validate filename if provided
	if filename then
		filename = validate_filename(filename, "R")
		if not filename then return end
	end
	
	-- Template content
	local template = {
		"# %%",
		"library(ggplot2)",
		"library(dplyr)",
		"library(tidyr)",
		"",
		"# %%",
		"# Your code here",
		"",
	}
	
	-- Create file with template
	if create_file_with_template(filename, template, "r") then
		if filename then
			vim.notify("✅ Created R notebook: " .. filename, vim.log.levels.INFO)
		else
			vim.notify("✅ Created new R notebook (use :w to save)", vim.log.levels.INFO)
		end
	end
end, { nargs = "?", desc = "Create new R file with cells" })

-- Helper function to create .ipynb files
local function create_ipynb_file(filename, language, kernel_info, imports)
	-- Ensure .ipynb extension
	if not filename:match("%.ipynb$") then
		filename = filename .. ".ipynb"
	end
	
	-- Check if file already exists
	if vim.fn.filereadable(filename) == 1 then
		local choice = vim.fn.confirm(
			"File '" .. filename .. "' already exists. Overwrite?",
			"&Yes\n&No",
			2
		)
		if choice ~= 1 then
			return false
		end
	end
	
	-- Generate unique cell IDs (required in nbformat 4.5+)
	local function generate_cell_id()
		local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
		local id = ""
		for i = 1, 8 do
			local idx = math.random(1, #chars)
			id = id .. chars:sub(idx, idx)
		end
		return id
	end

	-- Create notebook JSON structure
	local notebook = {
		cells = {
			{
				cell_type = "code",
				execution_count = vim.NIL,
				id = generate_cell_id(),
				metadata = vim.empty_dict(),
				outputs = {},
				source = imports
			},
			{
				cell_type = "code",
				execution_count = vim.NIL,
				id = generate_cell_id(),
				metadata = vim.empty_dict(),
				outputs = {},
				source = { "# Your code here" }
			}
		},
		metadata = kernel_info,
		nbformat = 4,
		nbformat_minor = 5
	}
	
	-- Try to encode JSON
	local ok, json_str = pcall(vim.json.encode, notebook)
	if not ok then
		vim.notify("❌ Failed to create notebook structure: " .. (json_str or "unknown error"), vim.log.levels.ERROR)
		return false
	end
	
	-- Write to file
	local file, err = io.open(filename, "w")
	if not file then
		vim.notify("❌ Failed to create file: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return false
	end
	
	local write_ok, write_err = pcall(function()
		file:write(json_str)
		file:close()
	end)
	
	if not write_ok then
		vim.notify("❌ Failed to write notebook: " .. (write_err or "unknown error"), vim.log.levels.ERROR)
		pcall(function() file:close() end)
		return false
	end
	
	-- Open the file
	local open_ok, open_err = pcall(vim.cmd, "edit " .. filename)
	if not open_ok then
		vim.notify("⚠️ Notebook created but failed to open: " .. (open_err or "unknown error"), vim.log.levels.WARN)
		vim.notify("You can open it manually: " .. filename, vim.log.levels.INFO)
		return true
	end
	
	vim.notify("✅ Created " .. language .. " notebook: " .. filename, vim.log.levels.INFO)
	return true
end

-- Create a new Python .ipynb notebook
vim.api.nvim_create_user_command("PyworksNewPythonNotebook", function(opts)
	local filename = opts.args ~= "" and opts.args or "notebook"
	
	-- Check for invalid characters
	if filename:match("[<>:|?*]") then
		vim.notify("❌ Invalid filename: " .. filename, vim.log.levels.ERROR)
		return
	end
	
	local kernel_info = {
		kernelspec = {
			display_name = "Python 3",
			language = "python",
			name = "python3"
		},
		language_info = {
			name = "python",
			version = "3.12.0"
		}
	}
	
	local imports = {
		"import numpy as np",
		"import pandas as pd",
		"import matplotlib.pyplot as plt"
	}
	
	create_ipynb_file(filename, "Python", kernel_info, imports)
end, { nargs = "?", desc = "Create new Python .ipynb notebook" })

-- Create a new Julia .ipynb notebook
vim.api.nvim_create_user_command("PyworksNewJuliaNotebook", function(opts)
	local filename = opts.args ~= "" and opts.args or "notebook"
	
	-- Check for invalid characters
	if filename:match("[<>:|?*]") then
		vim.notify("❌ Invalid filename: " .. filename, vim.log.levels.ERROR)
		return
	end
	
	local kernel_info = {
		kernelspec = {
			display_name = "Julia",
			language = "julia",
			name = "julia"
		},
		language_info = {
			name = "julia",
			version = "1.10.0"
		}
	}
	
	local imports = {
		"using Plots",
		"using DataFrames",
		"using Statistics"
	}
	
	create_ipynb_file(filename, "Julia", kernel_info, imports)
end, { nargs = "?", desc = "Create new Julia .ipynb notebook" })

-- Create a new R .ipynb notebook
vim.api.nvim_create_user_command("PyworksNewRNotebook", function(opts)
	local filename = opts.args ~= "" and opts.args or "notebook"
	
	-- Check for invalid characters
	if filename:match("[<>:|?*]") then
		vim.notify("❌ Invalid filename: " .. filename, vim.log.levels.ERROR)
		return
	end
	
	local kernel_info = {
		kernelspec = {
			display_name = "R",
			language = "R",
			name = "ir"
		},
		language_info = {
			name = "R",
			version = "4.3.0"
		}
	}
	
	local imports = {
		"library(ggplot2)",
		"library(dplyr)",
		"library(tidyr)"
	}
	
	create_ipynb_file(filename, "R", kernel_info, imports)
end, { nargs = "?", desc = "Create new R .ipynb notebook" })

return M