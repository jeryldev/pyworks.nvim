-- Commands for creating new notebook files
local M = {}

-- Create a new Python file with cell markers
vim.api.nvim_create_user_command("PyworksNewPython", function(opts)
	local filename = opts.args ~= "" and opts.args or nil
	
	if filename then
		-- Ensure .py extension
		if not filename:match("%.py$") then
			filename = filename .. ".py"
		end
		vim.cmd("edit " .. filename)
	else
		-- Create unnamed buffer
		vim.cmd("enew")
	end
	
	-- Add template content
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {
		"# %%",
		"import numpy as np",
		"import pandas as pd",
		"import matplotlib.pyplot as plt",
		"",
		"# %%",
		"# Your code here",
		"",
	})
	
	-- Set filetype for syntax highlighting
	vim.bo.filetype = "python"
	
	if filename then
		vim.notify("Created Python notebook: " .. filename, vim.log.levels.INFO)
	else
		vim.notify("Created new Python notebook (use :w to save)", vim.log.levels.INFO)
	end
end, { nargs = "?", desc = "Create new Python file with cells" })

-- Create a new Julia file with cell markers
vim.api.nvim_create_user_command("PyworksNewJulia", function(opts)
	local filename = opts.args ~= "" and opts.args or nil
	
	if filename then
		-- Ensure .jl extension
		if not filename:match("%.jl$") then
			filename = filename .. ".jl"
		end
		vim.cmd("edit " .. filename)
	else
		-- Create unnamed buffer
		vim.cmd("enew")
	end
	
	-- Add template content
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {
		"# %%",
		"using Plots",
		"using DataFrames",
		"using Statistics",
		"",
		"# %%",
		"# Your code here",
		"",
	})
	
	-- Set filetype for syntax highlighting
	vim.bo.filetype = "julia"
	
	if filename then
		vim.notify("Created Julia notebook: " .. filename, vim.log.levels.INFO)
	else
		vim.notify("Created new Julia notebook (use :w to save)", vim.log.levels.INFO)
	end
end, { nargs = "?", desc = "Create new Julia file with cells" })

-- Create a new R file with cell markers
vim.api.nvim_create_user_command("PyworksNewR", function(opts)
	local filename = opts.args ~= "" and opts.args or nil
	
	if filename then
		-- Ensure .R extension
		if not filename:match("%.R$") then
			filename = filename .. ".R"
		end
		vim.cmd("edit " .. filename)
	else
		-- Create unnamed buffer
		vim.cmd("enew")
	end
	
	-- Add template content
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {
		"# %%",
		"library(ggplot2)",
		"library(dplyr)",
		"library(tidyr)",
		"",
		"# %%",
		"# Your code here",
		"",
	})
	
	-- Set filetype for syntax highlighting
	vim.bo.filetype = "r"
	
	if filename then
		vim.notify("Created R notebook: " .. filename, vim.log.levels.INFO)
	else
		vim.notify("Created new R notebook (use :w to save)", vim.log.levels.INFO)
	end
end, { nargs = "?", desc = "Create new R file with cells" })

-- Create a new Python .ipynb notebook
vim.api.nvim_create_user_command("PyworksNewPythonNotebook", function(opts)
	local filename = opts.args ~= "" and opts.args or "notebook"
	
	-- Ensure .ipynb extension
	if not filename:match("%.ipynb$") then
		filename = filename .. ".ipynb"
	end
	
	-- Create notebook JSON structure
	local notebook = {
		cells = {
			{
				cell_type = "code",
				execution_count = nil,
				metadata = {},
				outputs = {},
				source = {
					"import numpy as np",
					"import pandas as pd",
					"import matplotlib.pyplot as plt"
				}
			},
			{
				cell_type = "code",
				execution_count = nil,
				metadata = {},
				outputs = {},
				source = {
					"# Your code here"
				}
			}
		},
		metadata = {
			kernelspec = {
				display_name = "Python 3",
				language = "python",
				name = "python3"
			},
			language_info = {
				name = "python",
				version = "3.12.0"
			}
		},
		nbformat = 4,
		nbformat_minor = 5
	}
	
	-- Write to file
	local file = io.open(filename, "w")
	if file then
		file:write(vim.json.encode(notebook))
		file:close()
		
		-- Open the file
		vim.cmd("edit " .. filename)
		vim.notify("Created Python notebook: " .. filename, vim.log.levels.INFO)
	else
		vim.notify("Failed to create notebook file", vim.log.levels.ERROR)
	end
end, { nargs = "?", desc = "Create new Python .ipynb notebook" })

-- Create a new Julia .ipynb notebook
vim.api.nvim_create_user_command("PyworksNewJuliaNotebook", function(opts)
	local filename = opts.args ~= "" and opts.args or "notebook"
	
	-- Ensure .ipynb extension
	if not filename:match("%.ipynb$") then
		filename = filename .. ".ipynb"
	end
	
	-- Create notebook JSON structure
	local notebook = {
		cells = {
			{
				cell_type = "code",
				execution_count = nil,
				metadata = {},
				outputs = {},
				source = {
					"using Plots",
					"using DataFrames",
					"using Statistics"
				}
			},
			{
				cell_type = "code",
				execution_count = nil,
				metadata = {},
				outputs = {},
				source = {
					"# Your code here"
				}
			}
		},
		metadata = {
			kernelspec = {
				display_name = "Julia",
				language = "julia",
				name = "julia"
			},
			language_info = {
				name = "julia",
				version = "1.10.0"
			}
		},
		nbformat = 4,
		nbformat_minor = 5
	}
	
	-- Write to file
	local file = io.open(filename, "w")
	if file then
		file:write(vim.json.encode(notebook))
		file:close()
		
		-- Open the file
		vim.cmd("edit " .. filename)
		vim.notify("Created Julia notebook: " .. filename, vim.log.levels.INFO)
	else
		vim.notify("Failed to create notebook file", vim.log.levels.ERROR)
	end
end, { nargs = "?", desc = "Create new Julia .ipynb notebook" })

-- Create a new R .ipynb notebook
vim.api.nvim_create_user_command("PyworksNewRNotebook", function(opts)
	local filename = opts.args ~= "" and opts.args or "notebook"
	
	-- Ensure .ipynb extension
	if not filename:match("%.ipynb$") then
		filename = filename .. ".ipynb"
	end
	
	-- Create notebook JSON structure
	local notebook = {
		cells = {
			{
				cell_type = "code",
				execution_count = nil,
				metadata = {},
				outputs = {},
				source = {
					"library(ggplot2)",
					"library(dplyr)",
					"library(tidyr)"
				}
			},
			{
				cell_type = "code",
				execution_count = nil,
				metadata = {},
				outputs = {},
				source = {
					"# Your code here"
				}
			}
		},
		metadata = {
			kernelspec = {
				display_name = "R",
				language = "R",
				name = "ir"
			},
			language_info = {
				name = "R",
				version = "4.3.0"
			}
		},
		nbformat = 4,
		nbformat_minor = 5
	}
	
	-- Write to file
	local file = io.open(filename, "w")
	if file then
		file:write(vim.json.encode(notebook))
		file:close()
		
		-- Open the file
		vim.cmd("edit " .. filename)
		vim.notify("Created R notebook: " .. filename, vim.log.levels.INFO)
	else
		vim.notify("Failed to create notebook file", vim.log.levels.ERROR)
	end
end, { nargs = "?", desc = "Create new R .ipynb notebook" })

return M