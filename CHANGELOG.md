# Changelog

All notable changes to pyworks.nvim will be documented in this file.

## [2.0.0] - 2024-01-08

### Added
- **Multi-language Kernel Support**: Automatic detection and initialization for Python, Julia, and R
- **Consistent Notification Workflow**: All file types show same detailed progress notifications
- **Smart Package Detection**: Auto-detects missing Python packages with compatibility checks
- **Kernel Memory**: Remembers previous kernel selections for faster future initialization
- **Package Compatibility Handling**: Detects and warns about Python 3.12+ incompatibilities
- **Alternative Package Suggestions**: Recommends compatible alternatives (e.g., PyTorch for TensorFlow)
- **Enhanced Output Windows**: Increased to 40x150 for better data visualization
- **Immediate File Detection**: Shows notifications as soon as files are opened
- **Comprehensive Error Messages**: Clear guidance for recovery from issues

### Changed
- **Unified Experience**: Same workflow for .py, .jl, .R, and .ipynb files
- **Better Package Detection**: Handles complex import patterns and package name mappings
- **Improved Kernel Matching**: Smart detection based on file type and notebook metadata
- **Non-silent Initialization**: All file types now show detailed initialization progress
- **Optimized Autocmds**: Faster file detection with immediate notifications

### Fixed
- Unicode separator corruption in notifications
- Package installation command format issues
- Silent mode inconsistencies between file types
- Notebook metadata detection for non-Python languages
- Kernel initialization race conditions
- Package name mapping (scikit-learn → scikit-learn, PIL → Pillow)

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