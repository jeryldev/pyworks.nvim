# Changelog

All notable changes to pyworks.nvim will be documented in this file.

## [Unreleased]

### Changed

- **Removed floating window keymaps (`<leader>jo`, `<leader>jh`, `K`)** - These controlled Molten's
  floating output window which is not Jupyter-like. Output now follows Jupyter behavior:
  - Output appears inline below cells (Molten's default)
  - Use `<leader>jd` to clear output
  - Use `<leader>jj` to re-run cell and see output again
  - Removed `K` override - use your existing LSP hover configuration

- **Breaking: Removed jupytext.nvim dependency** - pyworks.nvim now handles .ipynb files directly
  - Uses jupytext CLI directly for notebook conversion (automatically installed as Python package)
  - No longer requires jupytext.nvim plugin in dependencies
  - Prevents autocmd conflicts and E325 swap file errors
  - Disables swap files for .ipynb buffers to avoid interactive prompt issues
  - Provides graceful fallback to JSON view when jupytext CLI is not installed
  - Auto-detects jupytext.nvim and warns about potential conflicts
  - Set `skip_jupytext = true` if you prefer to use jupytext.nvim instead
  - Update your lazy.nvim config to remove jupytext.nvim from dependencies

### Fixed

- **Molten extmark bug workaround**: Added event suppression during run-all cell execution
  - Prevents IndexError when Molten accesses invalid extmarks during rapid cursor navigation
  - Calls MoltenDeinit before notebook buffer reloads and on session restore
  - Workaround for upstream Molten bug in position.py

- **Breaking: Reorganized Cell Execution and Folding Keymaps**:
  - `<leader>jj` - Run cell and move to next (was `<leader>jc`)
  - `<leader>jc` - Collapse current cell (NEW)
  - `<leader>jC` - Collapse all cells (was `<leader>jzc`)
  - `<leader>je` - Expand current cell (was "re-evaluate current cell")
  - `<leader>jE` - Expand all cells (was `<leader>jze`)
  - Removed `<leader>je` for re-evaluate (redundant with `<leader>jj`)
- **Improved Cell Folding**: Collapse/expand commands now auto-enable folding if not already active

### Added

- **Configurable Custom Package Prefixes**: Package detection now supports user-defined prefixes
  - Configure via `packages.custom_package_prefixes` in setup()
  - Default prefixes: `^my_`, `^custom_`, `^local_`, `^internal_`, `^private_`, `^app_`, `^lib_`, `^src$`, `^utils$`, `^helpers$`
  - Prevents suggesting installation of company-internal or local packages
- **Test Coverage for UI Module**: Added comprehensive tests for ui.lua
  - Tests for cell highlighting, execution tracking, numbering, and folding
  - 11 new test cases covering all major UI functions
- **Run All Cells (`<leader>jR`)**: Execute all cells sequentially from top to bottom
  - Automatically finds and counts all cells in the buffer
  - Runs cells with 200ms delay to prevent kernel overload
  - Shows progress notification and restores cursor position when complete
  - Works with both code and markdown cells (markdown cells are skipped by kernel)
- **Cell Folding & UI Enhancements**: New visual features for better cell organization
  - Cell folding: Collapse/expand cells with `<leader>jf`, `<leader>jc/jC`, `<leader>je/jE`
  - Cell numbering: Automatic inline cell numbering with type indicators (code/markdown)
  - Execution status: Cell numbers change from red (unrun) to green (executed) when cells are run
  - Tracks execution state per buffer - visual feedback for which cells have been executed
  - Custom fold text showing cell type, line count, and content preview
  - Configurable via `setup({ show_cell_numbers = true, enable_cell_folding = false })`
- **15 New Jupyter-like Keybindings**: Comprehensive cell manipulation and execution
  - Cell execution: `<leader>jj` (run and move next)
  - Cell creation: `<leader>ja/jb` (insert code cells above/below), `<leader>jma/jmb` (insert markdown cells)
  - Cell operations: `<leader>jt` (toggle type), `<leader>jJ` (merge below), `<leader>js` (split at cursor)
  - Output management: `<leader>jd` (delete), `<leader>jh` (hide), `<leader>jo` (enter window)
  - Navigation: `<leader>jg` (go to cell N - now works without running cells)
  - Kernel management: `<leader>mi` (initialize), `<leader>mI` (show info)

### Fixed

- **Security: Pip Action Whitelist**: Added validation for pip command actions
  - Only allows safe actions: install, uninstall, list, show, freeze
  - Prevents potential command injection via malicious package names
- **Security: File Size Check**: Added size limit before reading files for import scanning
  - Prevents memory issues with very large files
  - Default limit: 1MB (configurable)
- **Cell Toggle (`<leader>jt`)**: Fixed toggle not working from markdown back to code
  - Simplified pattern matching to check for `[markdown]` substring instead of complex regex
  - Now correctly toggles between `# %%` and `# %% [markdown]` in both directions
- **Cell Navigation (`<leader>jg`)**: Reimplemented to work without executing cells
  - Previously used `MoltenGoto` which required cells to be executed first
  - Now searches for `# %%` markers directly, enabling navigation before execution
  - Shows helpful error if requested cell number doesn't exist
  - Restores cursor position on error for better UX
- **Molten Cell Execution for Percent-Format Scripts**: Fixed "not in a cell" errors
  - `<leader>jc` and `<leader>je` now work correctly with `# %%` delimited cells
  - Added `evaluate_percent_cell()` helper that finds code between `# %%` markers
  - Properly excludes `# %%` markers from execution (only executes cell content)
  - Uses visual selection to create Molten cells on-the-fly
  - Keybindings now work whether or not a Molten cell exists
- **Cursor Movement After Cell Execution**: Fixed `<leader>jc` not moving to next cell
  - Removed cursor restoration from `evaluate_percent_cell()` to prevent overwriting navigation
  - Added proper cursor positioning control in `<leader>jc` (move to next) and `<leader>je` (stay in place)
  - Cell execution now properly mimics Jupyter's Shift+Enter behavior

### Changed

- **Code Quality: Extracted filter_pip_stderr Helper**: Reduced complexity in python.lua
  - Filters out pip noise (WARNING, Resolved, Installed, Collecting messages)
  - Cleaner error output for package installation failures
- **Breaking**: `<leader>jj` is now "run cell and move to next" (was `<leader>jc`)
  - `<leader>jc` is now "collapse current cell"
  - Use `<leader>jv` for visual select cell (better vim semantics)
- **Documentation**: Simplified README and help docs by removing verbose sections
  - Removed "Why This Simple Configuration Works" section
  - Removed "What's New in v3.0" marketing language
  - Removed "The Six Core Scenarios" section
  - Consolidated Jupyter Notebook Support into Quick Start
- **Focus**: Simplified to Python-only
  - Removed Julia and R language support
  - Renamed package commands for clarity (Sync/Add/Remove/List)
  - Added `:PyworksHelp` command for quick reference

### Documentation

- **Fixed Neovim Version Requirement**: Updated from ≥0.9.0 to ≥0.10.0 (code uses `vim.system()` and `vim.uv` APIs)
- **Expanded Project Detection Markers**: Documented all 16+ supported markers including uv.lock, poetry.lock, manage.py, etc.
- **Added Missing Keymaps to Help Doc**: Added `<leader>jR`, `<leader>jf`, `<leader>jc/jC`, `<leader>je/jE`, `<leader>jn`
- **Synced Configuration Section**: README now matches actual init.lua defaults
- Added active development warning to README
- Updated all keybinding tables with comprehensive new set (24 total keybindings)
- Reorganized keybindings into logical categories (Execution, Navigation, Output, Creation, Operations, Kernel)
- Updated typical workflow examples with new keybindings

## [3.0.2] - 2025-01-08

### Added

- **Notebook Creation Commands**: Commands for creating notebooks with templates
  - `:PyworksNewPython [name]` - Create Python file with cell markers and common imports
  - `:PyworksNewPythonNotebook [name]` - Create proper .ipynb with Python kernel
- **LazyVim Configuration Example**: Added `examples/lazyvim-setup.lua` with exact working configuration
- **Molten Virtual Text Output**: Enabled `molten_virt_text_output=true` for persistent cell output with images

### Fixed

- **Configuration Order**: Fixed jupytext.nvim to use `config = true` for proper setup
- **Molten Cell Persistence**: Cells now properly show output when cursor returns to them
- **Image Display**: Images now display correctly in Molten output windows alongside text

### Documentation

- Added complete workflow guide in README
- Updated help file with practical examples and quick start guide
- Cleaned up outdated commands and non-existent features
- Added comprehensive command and keymap reference tables

## [3.0.1] - 2025-01-08

### Added

- **Python Package Management Commands**:
  - `:PyworksAdd <packages>` - Add packages to project venv
  - `:PyworksRemove <packages>` - Remove packages from project venv
  - `:PyworksList` - List all installed packages in a buffer
  - `:PyworksSync` - Install missing packages detected from imports
- **Enhanced Error Reporting**: Detailed error buffers for package installation failures with full output and troubleshooting steps
- **Smart Package Filtering**:
  - Automatically ignores standard library modules (base64, os, sys, etc.)
  - Filters out custom/local packages (company-specific prefixes like seell_, my_, internal_)
  - Only suggests real PyPI packages for installation

### Fixed

- **Per-Project Python Configuration**: Each project now correctly uses its own Python environment
- **UV/pip Detection**: Improved detection of UV vs regular pip virtual environments
  - Checks for `uv = ` marker in pyvenv.cfg
  - Verifies uv.lock presence
  - Falls back to pip for non-UV venvs
- **File Path Handling**: Consistent use of absolute paths throughout the codebase
- **Package Installation**: Better handling of missing packages with improved logging

### Changed

- **Package Detection Logic**: More robust filtering to avoid installing non-existent packages
- **Virtual Environment Detection**: Now uses file's directory instead of current working directory
- **Error Messages**: More informative error messages with actionable troubleshooting steps

## [3.0.0] - 2024-08-08

### Major Rewrite - Complete Architecture Overhaul

#### Added

- **Zero-Configuration Workflow**: Automatic environment setup for Python without any manual steps
- **Auto-Initialization**: Molten kernels initialize automatically when compatible kernel exists
- **Dynamic Kernel Detection**: Queries available kernels instead of hardcoded names
- **Project-Based Activation**: Only runs in directories with project markers (.venv, pyproject.toml, etc.)
- **Hover-Based Output**: Molten outputs display on demand, not inline (cleaner workspace)
- **Smart Package Detection**: Improved detection with proper async handling
- **Cell Navigation**: [j and ]j keymaps for navigating between cells (avoiding LazyVim conflicts)
- **Visual Selection Fix**: Proper handling of visual mode for cell execution

#### Changed

- **Complete Restructure**: Modular architecture with separate core, languages, and notebook modules
- **Improved Caching**: Aggressive caching with TTL for better performance
- **Better Notifications**: Only shows notifications when action needed, silent when ready
- **Jupytext Integration**: Automatic jupytext installation and PATH configuration
- **Image Display**: Fixed to show only in Molten popup, not external applications

#### Fixed

- **Kernel Name Mismatch**: Kernels now detected dynamically
- **Visual Selection Error**: "No visual selection found" error with proper `:<C-u>` handling
- **Auto-Initialization**: Now works for all 6 scenarios including notebooks
- **Package Installation**: Notifications only show after actual completion
- **Global Activation**: Pyworks only activates in project directories
- **Image Popup**: Disabled auto_image_popup to prevent external viewer launches

#### Removed

- **Legacy Code**: Removed all v2 code and migrated to clean v3 architecture
- **Test Files**: Moved all tests and documentation to notes/ folder
- **Redundant Features**: Removed duplicate functionality and streamlined workflows

## [2.0.0] - 2024-01-08

### Added

- **Python Kernel Support**: Automatic detection and initialization for Python
- **Smart Package Detection**: Auto-detects missing Python packages with compatibility checks
- **Package Compatibility Handling**: Detects and warns about Python 3.12+ incompatibilities
- **Alternative Package Suggestions**: Recommends compatible alternatives (e.g., PyTorch for TensorFlow)
- **Enhanced Output Windows**: Increased to 40x150 for better data visualization
- **Consistent Workflow**: All file types trigger same detection and initialization flow

### Changed

- **Unified Experience**: Same workflow for .py and .ipynb files
- **Better Package Detection**: Handles complex import patterns and package name mappings
- **Improved Kernel Matching**: Smart detection based on file type and notebook metadata
- **Optimized Autocmds**: Immediate notifications with deferred initialization

### Fixed

- Unicode separator corruption in notifications
- Package installation command format issues
- Silent mode inconsistencies between file types
- Notebook metadata detection for non-Python languages
- Kernel initialization race conditions
- Package name mapping (scikit-learn, PIL → Pillow)

## [1.5.0] - 2024-01-07

### Performance Improvements

### 1. Implemented Caching Layer ✅

- Added `utils.get_cached()` function for expensive operations
- Cache Jupyter availability checks (30 second TTL)
- Cache kernel list fetching (10 second TTL)
- Reduces repeated file system calls

### 2. Extracted Common venv Logic ✅

- New utility functions in `utils.lua`:
  - `has_venv()` - Check if virtual environment exists
  - `get_python_path()` - Get Python executable from venv
  - `is_venv_configured()` - Check if venv is properly set up
  - `ensure_venv_in_path()` - Add venv to PATH
- Eliminated code duplication across modules

### 3. Converted Critical Blocking Calls to Async ✅

- `complete_setup()` now uses async for:
  - Remote plugin updates
  - Jupyter kernel creation
  - Package installation checks
- UI no longer freezes during setup operations

### 4. Documentation Updates ✅

- Removed outdated `docs/` folder
- Updated README configuration section
- Removed misleading Molten configuration options

## Performance Impact

### Before

- Setup operations blocked UI for 5-30 seconds
- Repeated kernel checks every time Molten initialized
- Multiple redundant filesystem checks

### After

- Setup runs in background with progress indicators
- Kernel list cached for 10 seconds
- Jupyter availability cached for 30 seconds
- Shared venv utilities reduce redundant checks

## Still To Do

1. **Break down complex functions in setup.lua**

   - Split large functions into smaller, testable units
   - Improve readability and maintainability

2. **Additional async conversions**

   - Package availability checks
   - Environment diagnostics

3. **Further caching opportunities**
   - Notebook metadata parsing
   - Package list caching

## Testing Recommendations

1. Test setup with slow network (package installation)
2. Verify kernel list caching works correctly
3. Ensure async operations complete properly
4. Check that cache invalidation works as expected

