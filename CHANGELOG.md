# Changelog

All notable changes to pyworks.nvim will be documented in this file.

## [3.0.2] - 2025-01-08

### Added

- **Notebook Creation Commands**: Six new commands for creating notebooks with templates
  - `:PyworksNewPython [name]` - Create Python file with cell markers and common imports
  - `:PyworksNewJulia [name]` - Create Julia file with Plots, DataFrames imports
  - `:PyworksNewR [name]` - Create R file with ggplot2, dplyr libraries
  - `:PyworksNewPythonNotebook [name]` - Create proper .ipynb with Python kernel
  - `:PyworksNewJuliaNotebook [name]` - Create .ipynb with Julia kernel metadata
  - `:PyworksNewRNotebook [name]` - Create .ipynb with R kernel metadata
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
  - `:PyworksInstallPython <packages>` - Install Python packages in project venv
  - `:PyworksUninstallPython <packages>` - Uninstall packages from project venv
  - `:PyworksListPython` - List all installed Python packages in a buffer
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

- **Zero-Configuration Workflow**: Automatic environment setup for Python, Julia, and R without any manual steps
- **Auto-Initialization**: Molten kernels initialize automatically when compatible kernel exists
- **Dynamic Kernel Detection**: Queries available kernels instead of hardcoded names (fixes julia-1.11 issue)
- **Project-Based Activation**: Only runs in directories with project markers (.venv, Project.toml, etc.)
- **Hover-Based Output**: Molten outputs display on demand, not inline (cleaner workspace)
- **Smart Package Detection**: Improved detection for all three languages with proper async handling
- **Cell Navigation**: [j and ]j keymaps for navigating between cells (avoiding LazyVim conflicts)
- **Visual Selection Fix**: Proper handling of visual mode for cell execution

#### Changed

- **Complete Restructure**: Modular architecture with separate core, languages, and notebook modules
- **Improved Caching**: Aggressive caching with TTL for better performance
- **Better Notifications**: Only shows notifications when action needed, silent when ready
- **Jupytext Integration**: Automatic jupytext installation and PATH configuration
- **Image Display**: Fixed to show only in Molten popup, not external applications

#### Fixed

- **Kernel Name Mismatch**: Julia kernels (julia-1.11) now detected dynamically
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

- **Multi-language Kernel Support**: Automatic detection and initialization for Python, Julia, and R
- **Smart Package Detection**: Auto-detects missing Python packages with compatibility checks
- **Package Compatibility Handling**: Detects and warns about Python 3.12+ incompatibilities
- **Alternative Package Suggestions**: Recommends compatible alternatives (e.g., PyTorch for TensorFlow)
- **Enhanced Output Windows**: Increased to 40x150 for better data visualization
- **Consistent Workflow**: All file types trigger same detection and initialization flow

### Changed

- **Unified Experience**: Same workflow for .py, .jl, .R, and .ipynb files
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

