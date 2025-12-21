# Pyworks.nvim Tests

Comprehensive test suite for pyworks.nvim using Plenary.nvim test framework.

## Test Structure

```
tests/
├── minimal_init.lua           # Minimal Neovim config for testing
├── utils_spec.lua             # Tests for core utilities (project detection, caching, file ops)
├── detector_spec.lua          # Tests for file type detection and kernel management
├── notebook_handler_spec.lua  # Tests for notebook handling and jupytext integration
├── init_spec.lua              # Tests for configure_dependencies and jupytext race condition fix
├── create_spec.lua            # Tests for notebook creation commands and JSON validity
└── README.md                  # This file
```

## Running Tests

### Prerequisites

Install Plenary.nvim (test framework):
```bash
# Using lazy.nvim
# Add to your plugin config:
{ "nvim-lua/plenary.nvim" }
```

### Run All Tests

```bash
# From pyworks.nvim directory
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

### Run Specific Test File

```bash
nvim --headless -c "PlenaryBustedFile tests/utils_spec.lua"
```

### Run Tests in Neovim

```vim
:PlenaryBustedDirectory tests/
:PlenaryBustedFile tests/utils_spec.lua
```

## Test Coverage

### utils_spec.lua (Project Detection & Utilities)

**Covered:**
- ✅ Project root detection from nested files
- ✅ Venv path caching (including the bug fix)
- ✅ Different projects return different paths
- ✅ Graceful handling of non-existent files
- ✅ Project type detection (Django, Flask, Poetry, etc.)
- ✅ File operations (safe read/write)
- ✅ Async system calls
- ✅ Cache utilities with TTL expiration

**Critical Bug Tests:**
- ✅ Venv caching no longer returns wrong project for different files
- ✅ Cache key uses project_dir, not filepath

### detector_spec.lua (Kernel Management)

**Covered:**
- ✅ File routing (.py, .ipynb, .jl, .R)
- ✅ Invalid file path handling
- ✅ Notebook language detection from metadata
- ✅ Malformed JSON handling
- ✅ Buffer variable setting for PyworksSetup
- ✅ Warning when venv missing

**Critical Bug Tests:**
- ✅ Ipykernel validation before kernel creation
- ✅ Clear error messages when ipykernel missing

**Pending (Requires Mocking):**
- ⏳ Kernel creation with real Jupyter
- ⏳ Molten auto-initialization
- ⏳ Kernel name collision handling

### notebook_handler_spec.lua (Jupytext Integration)

**Covered:**
- ✅ Jupytext detection in project venv
- ✅ Jupytext detection in parent venv (nested directories)
- ✅ Fallback to system PATH
- ✅ Instructions when jupytext missing
- ✅ Different instructions for venv vs no-venv
- ✅ Project context in error messages

**Critical Bug Tests:**
- ✅ Finds jupytext in parent directory venv
- ✅ Checks project venv before system PATH

### init_spec.lua (Configuration & Race Condition Fix)

**Covered:**
- ✅ PATH updates with venv bin directories
- ✅ PATH updates with parent venv directories
- ✅ Conda environment PATH handling
- ✅ skip_jupytext option respected
- ✅ jupytext.setup() NOT called in configure_dependencies

**Critical Bug Tests:**
- ✅ Verifies race condition fix (no double jupytext.setup)
- ✅ Documents orphaned BufWriteCmd handlers issue
- ✅ Comments explain the fix in source code

**Pending:**
- ⏳ PATH deduplication on multiple calls

### create_spec.lua (Notebook Creation)

**Covered:**
- ✅ Creates valid JSON notebook files
- ✅ Proper nbformat 4.5 structure
- ✅ Cells have required fields (id, metadata, source)
- ✅ Auto-adds .ipynb extension
- ✅ Detects corrupted notebooks (percent format in .ipynb)

**Critical Bug Tests:**
- ✅ Newly created notebooks are valid JSON
- ✅ Notebooks start with '{' (JSON object)
- ✅ Notebooks don't contain jupytext header

## Test Patterns

### Mocking

Tests use simple Lua mocking patterns:

```lua
-- Save original
local original_func = module.some_function

-- Mock it
module.some_function = function(...)
    -- Mock implementation
end

-- Test...

-- Restore
module.some_function = original_func
```

### Temporary Files

All tests clean up temporary files:

```lua
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, "p")

-- ... test code ...

vim.fn.delete(temp_dir, "rf")  -- Always cleanup!
```

### Notifications

Track notifications for testing:

```lua
local notify_calls = {}
local original_notify = vim.notify
vim.notify = function(msg, level)
    table.insert(notify_calls, {msg = msg, level = level})
end

-- ... test code ...

vim.notify = original_notify
assert.is_true(#notify_calls > 0)
```

## Known Limitations

Some tests require external dependencies and are marked as `pending()`:

1. **Kernel Creation Tests** - Require Jupyter kernel infrastructure
2. **Molten Integration Tests** - Require molten.nvim plugin
3. **Real Python Execution** - Require Python environment setup

These can be implemented with more sophisticated mocking infrastructure.

## Adding New Tests

1. Create `*_spec.lua` file in `tests/` directory
2. Use `describe()` for test suites and `it()` for test cases
3. Use `assert.*` functions from Plenary
4. Always clean up temporary files
5. Mock external dependencies

Example:

```lua
local my_module = require("pyworks.my_module")

describe("my_module", function()
    describe("my_function", function()
        it("should do something", function()
            local result = my_module.my_function("input")
            assert.equals("expected", result)
        end)

        it("should handle errors", function()
            assert.has_error(function()
                my_module.my_function(nil)
            end)
        end)
    end)
end)
```

## Continuous Integration

To run tests in CI:

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Neovim
        run: |
          wget https://github.com/neovim/neovim/releases/download/stable/nvim-linux64.tar.gz
          tar xzf nvim-linux64.tar.gz
          echo "$PWD/nvim-linux64/bin" >> $GITHUB_PATH
      - name: Install Plenary
        run: |
          mkdir -p ~/.local/share/nvim/site/pack/vendor/start
          git clone https://github.com/nvim-lua/plenary.nvim \
            ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim
      - name: Run tests
        run: |
          nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

## Test Metrics

Current test coverage (as of 2025-12-21):

- **Total test files**: 5
- **Total test cases**: 60+
- **Coverage focus**: Critical bug fixes, race conditions, and core functionality
- **Pending tests**: 6 (require advanced mocking or future improvements)

## Contributing

When fixing bugs:
1. ✅ Write a failing test that demonstrates the bug
2. ✅ Fix the bug
3. ✅ Verify test passes
4. ✅ Commit both test and fix together

When adding features:
1. ✅ Write tests for new functionality
2. ✅ Implement the feature
3. ✅ Ensure all tests pass
4. ✅ Update this README
