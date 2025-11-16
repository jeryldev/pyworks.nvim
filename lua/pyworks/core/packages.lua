-- Universal package detection and management for pyworks.nvim

local M = {}

local cache = require("pyworks.core.cache")
local notifications = require("pyworks.core.notifications")
local state = require("pyworks.core.state")

-- Package name mappings for common mismatches
local package_mappings = {
  python = {
    ["sklearn"] = "scikit-learn",
    ["cv2"] = "opencv-python",
    ["PIL"] = "Pillow",
    ["bs4"] = "beautifulsoup4",
    ["sns"] = "seaborn",
    ["yaml"] = "PyYAML",
    ["discord"] = "discord.py",
    ["dotenv"] = "python-dotenv",
    ["rest_framework"] = "djangorestframework",
    ["magic"] = "python-magic",
    ["dateutil"] = "python-dateutil",
    ["jwt"] = "PyJWT",
    ["OpenSSL"] = "pyOpenSSL",
    ["serial"] = "pyserial",
    ["usb"] = "pyusb",
    ["Crypto"] = "pycryptodome",
    ["websocket"] = "websocket-client",
    ["google.cloud"] = "google-cloud-storage",
    ["cv"] = "opencv-python",
    ["wx"] = "wxPython",
    ["gi"] = "PyGObject",
    ["dbus"] = "dbus-python",
    ["apt"] = "python-apt",
    ["cairo"] = "pycairo",
  },
  julia = {
    -- Julia packages usually match their import names
  },
  r = {
    -- R packages usually match their library names
  },
}

-- Map import to package name
function M.map_import_to_package(import_name, language)
  language = language or "python"
  local mappings = package_mappings[language] or {}
  return mappings[import_name] or import_name
end

-- Extract imports from Python file
local function extract_python_imports(content)
  local imports = {}

  -- Match 'import package' and 'from package import ...'
  for line in content:gmatch("[^\r\n]+") do
    -- Skip comments
    if not line:match("^%s*#") then
      -- Match: import package, import package as alias
      local pkg = line:match("^%s*import%s+([%w_%.]+)")
      if pkg then
        -- Take only the root package
        local root = pkg:match("^([^%.]+)")
        imports[root] = true
      end

      -- Match: from package import ...
      pkg = line:match("^%s*from%s+([%w_%.]+)%s+import")
      if pkg then
        -- Take only the root package
        local root = pkg:match("^([^%.]+)")
        imports[root] = true
      end
    end
  end

  return vim.tbl_keys(imports)
end

-- Extract imports from Julia file
local function extract_julia_imports(content)
  local imports = {}

  for line in content:gmatch("[^\r\n]+") do
    -- Skip comments
    if not line:match("^%s*#") then
      -- Match: using Package, Package2
      local using_line = line:match("^%s*using%s+(.*)")
      if using_line then
        for pkg in using_line:gmatch("([%w_]+)") do
          imports[pkg] = true
        end
      end

      -- Match: import Package, Package2
      local import_line = line:match("^%s*import%s+(.*)")
      if import_line then
        for pkg in import_line:gmatch("([%w_]+)") do
          imports[pkg] = true
        end
      end
    end
  end

  return vim.tbl_keys(imports)
end

-- Extract imports from R file
local function extract_r_imports(content)
  local imports = {}

  for line in content:gmatch("[^\r\n]+") do
    -- Skip comments
    if not line:match("^%s*#") then
      -- Match: library(package) or library("package")
      local pkg = line:match("library%s*%([\"']?([%w_%.]+)[\"']?%)")
      if pkg then
        imports[pkg] = true
      end

      -- Match: require(package) or require("package")
      pkg = line:match("require%s*%([\"']?([%w_%.]+)[\"']?%)")
      if pkg then
        imports[pkg] = true
      end

      -- Match: pacman::p_load(package1, package2)
      local p_load = line:match("p_load%s*%((.*)%)")
      if p_load then
        for pkg in p_load:gmatch("[\"']?([%w_%.]+)[\"']?") do
          imports[pkg] = true
        end
      end
    end
  end

  return vim.tbl_keys(imports)
end

-- Scan file for imports
function M.scan_imports(filepath, language)
  -- Ensure we have an absolute path for consistent caching
  if filepath and not filepath:match("^/") then
    filepath = vim.fn.fnamemodify(filepath, ":p")
  end

  -- Try cache first
  local cache_key = "imports_" .. filepath .. "_" .. language
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  -- Read content (from buffer for notebooks, from file for others)
  local content

  -- For notebooks (.ipynb), read from buffer instead of file
  -- because jupytext has already converted it to code
  if filepath:match("%.ipynb$") then
    -- Find buffer with this file
    local bufnr = vim.fn.bufnr(filepath)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
      -- Read from buffer (converted content)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      content = table.concat(lines, "\n")
    else
      -- Fallback: try to read current buffer if it's the notebook
      local current_file = vim.api.nvim_buf_get_name(0)
      if current_file == filepath then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        content = table.concat(lines, "\n")
      else
        -- Can't read notebook content
        return {}
      end
    end
  else
    -- Regular files: read from disk
    local file = io.open(filepath, "r")
    if not file then
      return {}
    end
    content = file:read("*all")
    file:close()
  end

  -- Extract imports based on language
  local imports = {}
  if language == "python" then
    imports = extract_python_imports(content)
  elseif language == "julia" then
    imports = extract_julia_imports(content)
  elseif language == "r" then
    imports = extract_r_imports(content)
  end

  -- Cache the result
  cache.set(cache_key, imports)

  return imports
end

-- Get installed packages for a language
function M.get_installed_packages(language, filepath)
  -- Include filepath in cache key to ensure we check the right project
  local cache_key = "installed_packages_" .. language .. "_" .. (filepath or "global")
  local cached = cache.get(cache_key)
  if cached then
    return cached
  end

  local installed = {}

  if language == "python" then
    local python = require("pyworks.languages.python")
    installed = python.get_installed_packages(filepath) -- Pass filepath!
  elseif language == "julia" then
    local julia = require("pyworks.languages.julia")
    installed = julia.get_installed_packages(filepath) -- Pass filepath!
  elseif language == "r" then
    local r = require("pyworks.languages.r")
    installed = r.get_installed_packages(filepath) -- Pass filepath!
  end

  -- Cache the result
  cache.set(cache_key, installed)

  return installed
end

-- Detect missing packages
function M.detect_missing_packages(filepath, language)
  local imports = M.scan_imports(filepath, language)
  local installed = M.get_installed_packages(language, filepath) -- Pass filepath!

  -- Convert installed list to a set for faster lookup
  local installed_set = {}
  for _, pkg in ipairs(installed) do
    installed_set[pkg:lower()] = true
  end

  local missing = {}
  for _, import_name in ipairs(imports) do
    -- Skip standard library modules and custom/local packages
    if not M.is_stdlib(import_name, language) and not M.is_custom_package(import_name, language) then
      -- Map import name to package name
      local package_name = M.map_import_to_package(import_name, language)

      -- Check if installed
      if not installed_set[package_name:lower()] then
        table.insert(missing, package_name)
      end
    end
  end

  return missing
end

-- Check if a module is likely a custom/local package
function M.is_custom_package(module_name, language)
  if language == "python" then
    -- Patterns that suggest custom/local packages
    -- Custom packages often have company/project prefixes
    if
        module_name:match("^seell_")  -- SEELL specific
        or module_name:match("^my_")  -- Common custom prefix
        or module_name:match("^custom_") -- Common custom prefix
        or module_name:match("^local_") -- Common local prefix
        or module_name:match("^internal_") -- Internal packages
        or module_name:match("^private_")
    then                              -- Private packages
      return true
    end
  end
  return false
end

-- Check if a module is part of standard library
function M.is_stdlib(module_name, language)
  if language == "python" then
    -- Python standard library modules (partial list)
    local stdlib = {
      os = true,
      sys = true,
      re = true,
      json = true,
      math = true,
      random = true,
      datetime = true,
      time = true,
      collections = true,
      itertools = true,
      functools = true,
      pathlib = true,
      subprocess = true,
      threading = true,
      multiprocessing = true,
      queue = true,
      socket = true,
      http = true,
      urllib = true,
      email = true,
      html = true,
      xml = true,
      csv = true,
      io = true,
      string = true,
      typing = true,
      types = true,
      enum = true,
      dataclasses = true,
      abc = true,
      copy = true,
      pickle = true,
      shelve = true,
      sqlite3 = true,
      zlib = true,
      gzip = true,
      hashlib = true,
      hmac = true,
      secrets = true,
      uuid = true,
      base64 = true,
      codecs = true,
      argparse = true,
      logging = true,
      configparser = true,
      tempfile = true,
      shutil = true,
      glob = true,
      fnmatch = true,
      inspect = true,
      traceback = true,
      warnings = true,
      contextlib = true,
      unittest = true,
      doctest = true,
      pdb = true,
      profile = true,
      asyncio = true,
      concurrent = true,
      contextvars = true,
      importlib = true,
      pkgutil = true,
      platform = true,
      errno = true,
      ctypes = true,
      struct = true,
      codecs = true,
      unicodedata = true,
      locale = true,
      gettext = true,
      statistics = true,
      decimal = true,
      fractions = true,
      numbers = true,
      cmath = true,
      array = true,
      weakref = true,
      gc = true,
      atexit = true,
      builtins = true,
    }
    return stdlib[module_name] == true
  elseif language == "julia" then
    -- Julia base modules
    local stdlib = {
      Base = true,
      Core = true,
      Main = true,
      LinearAlgebra = true,
      Statistics = true,
      Random = true,
      Dates = true,
      Printf = true,
      Unicode = true,
      Test = true,
      Pkg = true,
      REPL = true,
    }
    return stdlib[module_name] == true
  elseif language == "r" then
    -- R base packages
    local base = {
      base = true,
      utils = true,
      stats = true,
      graphics = true,
      grDevices = true,
      methods = true,
      datasets = true,
      grid = true,
      splines = true,
      stats4 = true,
      tcltk = true,
      tools = true,
      parallel = true,
      compiler = true,
    }
    return base[module_name] == true
  end

  return false
end

-- Install packages for a language
function M.install_packages(packages, language)
  if #packages == 0 then
    return
  end

  -- Delegate to language-specific installer
  if language == "python" then
    local python = require("pyworks.languages.python")
    python.install_packages(packages)
  elseif language == "julia" then
    local julia = require("pyworks.languages.julia")
    julia.install_packages(packages)
  elseif language == "r" then
    local r = require("pyworks.languages.r")
    r.install_packages(packages)
  end
end

-- Re-scan imports after file save
function M.rescan_for_language(filepath, language)
  -- Invalidate cache
  cache.invalidate("imports_" .. filepath .. "_" .. language)

  -- Detect missing packages
  local missing = M.detect_missing_packages(filepath, language)

  if #missing > 0 then
    notifications.notify_missing_packages(missing, language)
  end
end

-- Analyze current buffer
function M.analyze_buffer(language)
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    return { imports = {}, missing = {}, installed = {} }
  end

  -- Ensure absolute path
  if not filepath:match("^/") then
    filepath = vim.fn.fnamemodify(filepath, ":p")
  end

  local imports = M.scan_imports(filepath, language)
  local installed = M.get_installed_packages(language)
  local missing = M.detect_missing_packages(filepath, language)

  return {
    imports = imports,
    installed = installed,
    missing = missing,
  }
end

return M
