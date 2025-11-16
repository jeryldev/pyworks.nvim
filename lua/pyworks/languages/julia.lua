-- Julia language support for pyworks.nvim
-- Handles Julia files and notebooks with Julia kernels

local M = {}

local cache = require("pyworks.core.cache")
local notifications = require("pyworks.core.notifications")
local packages = require("pyworks.core.packages")
local state = require("pyworks.core.state")
local error_handler = require("pyworks.core.error_handler")

-- Check if Julia is installed
function M.has_julia()
  return vim.fn.executable("julia") == 1
end

-- Get Julia path
function M.get_julia_path()
  if vim.fn.executable("julia") == 1 then
    return "julia"
  end
  return nil
end

-- Check if IJulia is installed
function M.has_ijulia()
  -- Check cache first
  local cached = cache.get("ijulia_check")
  if cached ~= nil then
    return cached
  end

  local julia_path = M.get_julia_path()
  if not julia_path then
    cache.set("ijulia_check", false)
    return false
  end

  -- Check for IJulia package
  local cmd =
      string.format('%s -e "using Pkg; exit(in("IJulia", keys(Pkg.installed())) ? 0 : 1)" 2>/dev/null', julia_path)
  local result = vim.fn.system(cmd)
  local has_ijulia = vim.v.shell_error == 0

  -- Cache the result
  cache.set("ijulia_check", has_ijulia)

  return has_ijulia
end

-- Install IJulia
function M.install_ijulia()
  local julia_path = M.get_julia_path()
  if not julia_path then
    notifications.notify_error("Julia not found. Please install Julia first.")
    return false
  end

  notifications.progress_start("ijulia_install", "Julia Setup", "Installing IJulia kernel...")

  local cmd = string.format('%s -e "using Pkg; Pkg.add("IJulia"); using IJulia"', julia_path)

  vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      if code == 0 then
        cache.invalidate("ijulia_check")
        notifications.progress_finish("ijulia_install", "IJulia installed successfully")
        state.set("persistent_ijulia_installed", true)
      else
        notifications.progress_finish("ijulia_install")
        notifications.notify_error("Failed to install IJulia")
      end
    end,
  })

  return true
end

-- Ensure IJulia is available
function M.ensure_ijulia()
  if M.has_ijulia() then
    return true -- Already installed, nothing to do
  end

  -- Check if we've already prompted before
  local prompted = state.get("ijulia_prompted")
  if prompted then
    return false -- Already prompted, don't ask again
  end

  -- First time - ask user once
  state.set("ijulia_prompted", true)
  vim.ui.select({ "Yes", "No" }, {
    prompt = "IJulia kernel is required for Julia notebooks. Install it?",
  }, function(choice)
    if choice == "Yes" then
      M.install_ijulia()
    end
  end)
  return false
end

-- Check if Project.toml exists
function M.has_project()
  return vim.fn.filereadable("Project.toml") == 1
end

-- Activate project environment
function M.activate_project()
  if not M.has_project() then
    return true
  end

  local julia_path = M.get_julia_path()
  if not julia_path then
    return false
  end

  -- Activate the project
  local cmd = string.format('%s -e "using Pkg; Pkg.activate(".")"', julia_path)

  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

-- Get list of installed packages
function M.get_installed_packages(filepath)
  -- Julia packages are typically global or project-specific based on Project.toml
  -- For now, we'll check the global environment (filepath param kept for consistency)
  local julia_path = M.get_julia_path()
  if not julia_path then
    return {}
  end

  -- Get installed packages
  local cmd =
      string.format('%s -e "using Pkg; for (name, _) in Pkg.installed() println(name) end" 2>/dev/null', julia_path)

  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local installed = {}
  for line in output:gmatch("[^\r\n]+") do
    table.insert(installed, line:lower())
  end

  return installed
end

-- Check if a package is installed
function M.is_package_installed(package_name)
  local julia_path = M.get_julia_path()
  if not julia_path then
    return false
  end

  local cmd = string.format(
    '%s -e "using Pkg; exit(in("%s", keys(Pkg.installed())) ? 0 : 1)" 2>/dev/null',
    julia_path,
    package_name
  )

  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

-- Install packages
function M.install_packages(package_list)
  local julia_path = M.get_julia_path()
  if not julia_path then
    notifications.notify_error("Julia not found. Please install Julia first.")
    return false
  end

  if #package_list == 0 then
    return true
  end

  -- Activate project if exists
  if M.has_project() then
    M.activate_project()
  end

  notifications.progress_start(
    "julia_packages",
    "Installing Packages",
    string.format("Installing %d Julia packages...", #package_list)
  )

  -- Build Pkg.add command
  local pkg_adds = {}
  for _, pkg in ipairs(package_list) do
    table.insert(pkg_adds, string.format('Pkg.add("%s")', pkg))
  end

  local cmd = string.format('%s -e "using Pkg; %s"', julia_path, table.concat(pkg_adds, "; "))

  -- Create a job to install packages
  local job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      -- Update progress as packages install
      for _, line in ipairs(data) do
        if line:match("Installed") then
          notifications.progress_update("julia_packages", line, 75)
        end
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        notifications.progress_finish("julia_packages", "Julia packages installed successfully")
        -- Mark packages as installed
        for _, pkg in ipairs(package_list) do
          state.mark_package_installed("julia", pkg)
        end
        -- Invalidate cache
        cache.invalidate("installed_packages_julia")
      else
        notifications.progress_finish("julia_packages")
        notifications.notify_error("Failed to install some Julia packages")
      end

      -- Remove job from active jobs
      state.remove_job(job_id)
    end,
  })

  -- Track active job
  state.add_job(job_id, {
    type = "package_install",
    language = "julia",
    packages = package_list,
    started = os.time(),
  })

  return true
end

-- Ensure Julia environment is ready
function M.ensure_environment()
  -- Check cache first
  if not state.should_check("julia_env", "julia", 30) then
    return true
  end

  state.set_last_check("julia_env", "julia")

  -- Step 1: Check Julia installation
  if not M.has_julia() then
    notifications.notify(
      "Julia not found. Please install Julia from https://julialang.org",
      vim.log.levels.WARN,
      { action_required = true }
    )
    return false
  end

  -- Step 2: Activate project if exists
  if M.has_project() then
    M.activate_project()
  end

  -- Step 3: Notify environment ready
  notifications.notify_environment_ready("julia")

  return true
end

-- Handle Julia file
function M.handle_file(filepath, is_notebook)
  -- Ensure environment
  M.ensure_environment()

  -- If it's a notebook, ensure IJulia
  if is_notebook then
    M.ensure_ijulia()
  end

  -- Detect missing packages
  vim.defer_fn(function()
    local missing = packages.detect_missing_packages(filepath, "julia")

    if #missing > 0 then
      notifications.notify_missing_packages(missing, "julia")

      -- Store missing packages for leader-pi command
      state.set("missing_packages_julia", missing)
    else
      -- Clear any previous missing packages
      state.remove("missing_packages_julia")
    end
  end, 500) -- Small delay to let environment setup complete
end

-- Install missing packages command
function M.install_missing_packages()
  local missing = state.get("missing_packages_julia") or {}

  if #missing == 0 then
    notifications.notify("No missing Julia packages detected", vim.log.levels.INFO)
    return
  end

  M.install_packages(missing)
end

-- Setup Julia REPL integration
function M.setup_repl()
  -- This could integrate with iron.nvim or similar REPL plugins
  -- For now, just ensure Julia is available
  if not M.has_julia() then
    notifications.notify_error("Julia not found. Cannot start REPL.")
    return false
  end

  -- The actual REPL integration would be handled by iron.nvim
  return true
end

return M
