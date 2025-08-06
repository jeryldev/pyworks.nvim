-- Package detection and compatibility checking
local M = {}
local utils = require("pyworks.utils")

-- Common package name mappings (import name -> package name)
local package_mappings = {
	-- Scientific computing
	numpy = "numpy",
	np = "numpy",
	pandas = "pandas",
	pd = "pandas",
	scipy = "scipy",
	sklearn = "scikit-learn",
	
	-- Visualization
	matplotlib = "matplotlib",
	plt = "matplotlib",
	seaborn = "seaborn",
	sns = "seaborn",
	plotly = "plotly",
	px = "plotly",
	go = "plotly",
	
	-- Machine Learning
	tensorflow = "tensorflow",
	tf = "tensorflow",
	torch = "torch",
	pytorch = "torch",
	keras = "keras",
	xgboost = "xgboost",
	lightgbm = "lightgbm",
	
	-- Web frameworks
	fastapi = "fastapi",
	flask = "flask",
	django = "django",
	requests = "requests",
	httpx = "httpx",
	
	-- Data formats
	yaml = "pyyaml",
	cv2 = "opencv-python",
	PIL = "pillow",
	Image = "pillow",
	
	-- Jupyter/IPython
	IPython = "ipython",
	ipywidgets = "ipywidgets",
	jupyter = "jupyter",
	jupyterlab = "jupyterlab",
}

-- Python version compatibility issues
local compatibility_issues = {
	tensorflow = {
		max_version = "3.11",
		message = "TensorFlow doesn't support Python 3.12+ yet. Consider using Python 3.11 or earlier.",
		alternatives = { "torch", "jax" }
	},
	numba = {
		max_version = "3.11",
		message = "Numba may have issues with Python 3.12+. Consider Python 3.11 for stability.",
	},
}

-- Extract imports from Python code
function M.extract_imports(lines)
	local imports = {}
	local found_packages = {}
	
	for _, line in ipairs(lines) do
		-- Match "import package" or "import package as alias"
		local import_match = line:match("^import%s+([%w_%.]+)")
		if import_match then
			local base_package = import_match:match("^([^%.]+)")
			table.insert(imports, base_package)
			found_packages[base_package] = true
		end
		
		-- Match "from package import ..."
		local from_match = line:match("^from%s+([%w_%.]+)%s+import")
		if from_match then
			local base_package = from_match:match("^([^%.]+)")
			table.insert(imports, base_package)
			found_packages[base_package] = true
		end
		
		-- Match common aliases in comments like "# np for numpy"
		for alias, package in pairs(package_mappings) do
			if line:match("%s" .. alias .. "%s*=") or line:match("as%s+" .. alias) then
				found_packages[package] = true
			end
		end
	end
	
	-- Convert to list of unique packages
	local unique_packages = {}
	for pkg, _ in pairs(found_packages) do
		-- Map to actual package name
		local actual_package = package_mappings[pkg] or pkg
		
		-- Skip built-in modules
		if not M.is_builtin(actual_package) then
			table.insert(unique_packages, actual_package)
		end
	end
	
	return unique_packages
end

-- Check if a module is built-in
function M.is_builtin(module_name)
	local builtins = {
		-- Standard library modules
		"os", "sys", "re", "json", "math", "random", "datetime", "time",
		"collections", "itertools", "functools", "operator", "typing",
		"pathlib", "glob", "shutil", "tempfile", "subprocess", "threading",
		"multiprocessing", "asyncio", "socket", "http", "urllib", "email",
		"csv", "sqlite3", "pickle", "copy", "warnings", "logging", "unittest",
		"doctest", "pdb", "timeit", "trace", "io", "string", "textwrap",
		"unicodedata", "codecs", "encodings", "locale", "gettext", "struct",
		"hashlib", "hmac", "secrets", "uuid", "base64", "binascii", "zlib",
		"gzip", "bz2", "lzma", "zipfile", "tarfile", "configparser", "argparse",
		"getopt", "readline", "rlcompleter", "gc", "inspect", "ast", "dis",
		"types", "dataclasses", "enum", "abc", "contextlib", "decimal", "fractions",
		"numbers", "statistics", "queue", "heapq", "bisect", "array", "weakref",
		"pprint", "reprlib", "platform", "errno", "ctypes", "atexit", "traceback",
		"__future__", "builtins", "__builtin__",
	}
	
	for _, builtin in ipairs(builtins) do
		if module_name == builtin then
			return true
		end
	end
	
	return false
end

-- Check which packages are missing
function M.check_missing_packages(imports)
	local missing = {}
	local installed = {}
	
	-- Get Python path from virtual environment
	local python_path = vim.fn.getcwd() .. "/.venv/bin/python3"
	if vim.fn.executable(python_path) ~= 1 then
		python_path = vim.fn.exepath("python3")
	end
	
	for _, package in ipairs(imports) do
		-- Try to import the package
		local import_name = package
		
		-- Handle special cases where import name differs from package name
		if package == "scikit-learn" then
			import_name = "sklearn"
		elseif package == "pillow" then
			import_name = "PIL"
		elseif package == "opencv-python" then
			import_name = "cv2"
		elseif package == "pyyaml" then
			import_name = "yaml"
		end
		
		local cmd = string.format("%s -c 'import %s' 2>/dev/null", python_path, import_name)
		vim.fn.system(cmd)
		
		if vim.v.shell_error ~= 0 then
			table.insert(missing, package)
		else
			table.insert(installed, package)
		end
	end
	
	return missing, installed
end

-- Check Python version compatibility
function M.check_compatibility(packages)
	local issues = {}
	
	-- Get current Python version
	local python_path = vim.fn.getcwd() .. "/.venv/bin/python3"
	if vim.fn.executable(python_path) ~= 1 then
		python_path = vim.fn.exepath("python3")
	end
	
	local version_cmd = python_path .. " -c 'import sys; print(f\"{sys.version_info.major}.{sys.version_info.minor}\")'"
	local python_version = vim.fn.system(version_cmd):gsub("\n", "")
	
	for _, package in ipairs(packages) do
		local compat = compatibility_issues[package]
		if compat then
			-- Check if current Python version exceeds max supported
			if compat.max_version and python_version > compat.max_version then
				table.insert(issues, {
					package = package,
					message = compat.message,
					alternatives = compat.alternatives,
					python_version = python_version,
					max_supported = compat.max_version
				})
			end
		end
	end
	
	return issues
end

-- Analyze current buffer for imports
function M.analyze_buffer()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local imports = M.extract_imports(lines)
	
	if #imports == 0 then
		return
	end
	
	-- Check for missing packages
	local missing, installed = M.check_missing_packages(imports)
	
	-- Check for compatibility issues
	local compatibility = M.check_compatibility(imports)
	
	-- Report findings
	if #missing > 0 or #compatibility > 0 then
		vim.schedule(function()
			if #missing > 0 then
				utils.notify("📦 Missing packages detected: " .. table.concat(missing, ", "), vim.log.levels.WARN)
				
				-- Check if we have a virtual environment
				local has_venv = vim.fn.isdirectory(vim.fn.getcwd() .. "/.venv") == 1
				
				if not has_venv then
					utils.notify("💡 Run :PyworksSetup to create environment and install packages", vim.log.levels.INFO)
				else
					local install_cmd = ":PyworksInstallPackages " .. table.concat(missing, " ")
					utils.notify("💡 Run: " .. install_cmd, vim.log.levels.INFO)
					
					-- Store command for easy access
					vim.g.pyworks_suggested_install = install_cmd
					utils.notify("   Or press <leader>pi to install suggested packages", vim.log.levels.INFO)
				end
			end
			
			-- Report compatibility issues
			for _, issue in ipairs(compatibility) do
				utils.notify(
					string.format("⚠️  %s: %s", issue.package, issue.message),
					vim.log.levels.WARN
				)
				
				if issue.alternatives then
					utils.notify(
						"   Consider alternatives: " .. table.concat(issue.alternatives, ", "),
						vim.log.levels.INFO
					)
				end
			end
		end)
	end
	
	return {
		imports = imports,
		missing = missing,
		installed = installed,
		compatibility = compatibility
	}
end

-- Install suggested packages (called by keybinding)
function M.install_suggested()
	local cmd = vim.g.pyworks_suggested_install
	if cmd then
		utils.notify("Running command: " .. cmd, vim.log.levels.INFO)
		utils.notify("Current working directory: " .. vim.fn.getcwd(), vim.log.levels.INFO)
		vim.cmd(cmd)
		vim.g.pyworks_suggested_install = nil
	else
		utils.notify("No package suggestions available. Analyze the file first.", vim.log.levels.INFO)
	end
end

return M