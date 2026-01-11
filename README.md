# pyworks.nvim

**Zero-configuration Python notebook development for Neovim**

A Neovim plugin that provides automatic environment setup, package detection, and code execution for Python projects and Jupyter notebooks.

> ⚠️ **Active Development**: This plugin is under active development and may introduce breaking changes between versions. Check the [CHANGELOG](CHANGELOG.md) for migration guides when updating.

## Features

- **Zero Configuration** - Just open files and start coding
- **Auto Environment Setup** - Creates and manages virtual environments automatically
- **Smart Package Detection** - Detects and installs missing packages from imports
- **Jupyter Notebook Support** - Edit .ipynb files as naturally as .py files
- **Molten Integration** - Execute code cells with Jupyter-like experience
- **Inline Plots** - Display matplotlib output directly in Neovim
- **Cell Folding & Numbering** - Collapse/expand cells and see cell numbers inline
- **Execution Status Tracking** - Cell numbers turn green when executed, red when unrun
- **Project-Based Activation** - Only runs in actual project directories

## Requirements

- Neovim ≥ 0.10.0 (uses `vim.system()` and `vim.uv` APIs)
- Python 3.8+
- `jupytext` CLI (automatically installed by pyworks)
- Optional: [`uv`](https://github.com/astral-sh/uv) for faster package management (10-100x faster than pip)

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

Create `~/.config/nvim/lua/plugins/pyworks.lua`:

```lua
return {
  {
    "jeryldev/pyworks.nvim",
    dependencies = {
      "benlubas/molten-nvim",
      "3rd/image.nvim",
    },
    config = function()
      require("pyworks").setup({
        python = {
          use_uv = true,  -- Use uv for faster package installation
        },
        image_backend = "kitty",  -- or "ueberzug" for other terminals
      })
    end,
    lazy = false,
    priority = 100,
  },
}
```

Pyworks automatically:
- **Handles .ipynb files directly** - Uses jupytext CLI to convert notebooks to percent-style Python (`# %%`)
- **Detects jupytext CLI** - Checks PATH and common venv locations
- **Provides graceful fallback** - If jupytext CLI isn't installed, notebooks open as read-only JSON with helpful messages guiding you to run `:PyworksSetup`

### Terminal Requirements for Images

For inline plot/image display:
- **Kitty terminal** (recommended) - `brew install --cask kitty`
- **Ghostty terminal** (alternative) - Supports Kitty graphics protocol

## Quick Start

### Creating Notebooks

```vim
" Create Python file with cells
:PyworksNewPython analysis
" → Creates analysis.py with cell markers

" Create Jupyter notebook
:PyworksNewPythonNotebook report
" → Creates report.ipynb
```

### Typical Workflow

1. **Create a notebook**:
   ```vim
   :PyworksNewPython ml_model
   ```

2. **Write code** (cells marked with `# %%`):
   ```python
   # %%
   import numpy as np
   import pandas as pd

   # %%
   data = pd.read_csv('data.csv')
   print(data.head())
   ```

3. **Execute code**:
   - `<leader>jl` - Run current line (auto-initializes kernel on first use)
   - `<leader>jj` - Run cell and move to next (Shift+Enter in Jupyter)

4. **Create new cells**: `<leader>ja` / `jb` / `jma` / `jmb` (above/below, code/markdown)

5. **Package management**:
   - Missing packages detected automatically
   - Press `<leader>pi` to install missing packages
   - Or use `:PyworksAdd numpy pandas matplotlib`

## Key Bindings

### Cell Execution

| Keymap       | Mode   | Description                      |
| ------------ | ------ | -------------------------------- |
| `<leader>jl` | Normal | Run current line (auto-inits kernel) |
| `<leader>jr` | Visual | Run selection                    |
| `<leader>jj` | Normal | Run cell and move to next        |
| `<leader>jR` | Normal | Run all cells in buffer          |

### Cell Selection & Navigation

| Keymap       | Mode   | Description              |
| ------------ | ------ | ------------------------ |
| `<leader>jv` | Normal | Visual select current cell |
| `<leader>j]` | Normal | Next cell                |
| `<leader>j[` | Normal | Previous cell            |
| `<leader>jg` | Normal | Go to cell N (works without running cells) |

### Output Management

| Keymap       | Description              |
| ------------ | ------------------------ |
| `<leader>jd` | Clear cell output        |

### Cell Creation

| Keymap        | Description                   |
| ------------- | ----------------------------- |
| `<leader>ja`  | Insert code cell above        |
| `<leader>jb`  | Insert code cell below        |
| `<leader>jma` | Insert markdown cell above    |
| `<leader>jmb` | Insert markdown cell below    |

### Cell Operations

| Keymap       | Description                |
| ------------ | -------------------------- |
| `<leader>jt` | Toggle cell type (code ↔ markdown) |
| `<leader>jJ` | Merge with cell below      |
| `<leader>js` | Split cell at cursor       |

### Cell Folding & UI

| Keymap        | Description                    |
| ------------- | ------------------------------ |
| `<leader>jf`  | Toggle cell folding on/off     |
| `<leader>jc`  | Collapse current cell          |
| `<leader>jC`  | Collapse all cells             |
| `<leader>je`  | Expand current cell            |
| `<leader>jE`  | Expand all cells               |
| `<leader>jn`  | Refresh cell numbers           |

### Kernel Management

| Keymap       | Description         |
| ------------ | ------------------- |
| `<leader>mi` | Initialize kernel   |
| `<leader>mr` | Restart kernel      |
| `<leader>mx` | Interrupt execution |
| `<leader>mI` | Show kernel info    |

### Package Management

| Keymap       | Description                   |
| ------------ | ----------------------------- |
| `<leader>pi` | Install missing packages      |
| `<leader>ps` | Show package status           |

## Commands

### Notebook Creation

| Command                            | Description                        |
| ---------------------------------- | ---------------------------------- |
| `:PyworksNewPython [name]`         | Create Python file with cells      |
| `:PyworksNewPythonNotebook [name]` | Create Python Jupyter notebook     |

### Environment Management

| Command               | Description                                  |
| --------------------- | -------------------------------------------- |
| `:PyworksSetup`       | Create venv and install essential packages   |
| `:PyworksStatus`      | Show package status (imports/installed/missing) |
| `:PyworksDiagnostics` | Run diagnostics (environment, plugins, cache) |
| `:PyworksHelp`        | Show all commands and keymaps                |

### Package Management

| Command                     | Description                              |
| --------------------------- | ---------------------------------------- |
| `:PyworksSync`              | Install missing packages from imports    |
| `:PyworksAdd <packages>`    | Add packages to venv                     |
| `:PyworksRemove <packages>` | Remove packages from venv                |
| `:PyworksList`              | List all installed packages              |

## Configuration

### Default Settings (All Optional)

```lua
require("pyworks").setup({
  python = {
    use_uv = true,  -- Use uv for faster package management (10-100x faster than pip)
    preferred_venv_name = ".venv",
    auto_install_essentials = true,
    essentials = { "pynvim", "ipykernel", "jupyter_client", "jupytext", "numpy", "pandas", "matplotlib" },
  },
  packages = {
    -- Patterns for detecting custom/local packages (won't suggest installing these)
    custom_package_prefixes = {
      "^my_", "^custom_", "^local_", "^internal_", "^private_",
      "^app_", "^lib_", "^src$", "^utils$", "^helpers$",
    },
  },
  cache = {
    kernel_list = 60,        -- Cache TTL in seconds
    installed_packages = 300,
  },
  notifications = {
    verbose_first_time = true,
    silent_when_ready = true,
    show_progress = true,
    debug_mode = false,
  },
  auto_detect = true,  -- Automatically detect and setup on file open

  -- Optional: Skip auto-configuration of specific dependencies
  skip_molten = false,
  skip_jupytext = false,  -- Set to true if using jupytext.nvim plugin instead
  skip_image = false,
  skip_keymaps = false,
})
```

## How It Works

### Zero-Configuration Experience

1. **Open any Python file** - pyworks detects file type
2. **Automatic setup** - Creates environment, installs essentials
3. **Package detection** - Scans imports, shows missing packages
4. **Kernel initialization** - Auto-starts Python kernel
5. **Ready to code** - Use keymaps to execute code immediately

### Project Detection

Pyworks finds your project root by looking for these markers (in priority order):
- `.venv` - Virtual environment (highest priority)
- `pyproject.toml`, `setup.py`, `requirements.txt` - Python project files
- `manage.py`, `app.py`, `main.py` - Framework entry points (Django, Flask, FastAPI)
- `Pipfile`, `poetry.lock`, `uv.lock` - Package manager lock files
- `conda.yaml`, `environment.yml` - Conda environments
- `dvc.yaml`, `mlflow.yaml` - ML pipeline configs
- `.git` - Git repository (lowest priority fallback)

### Smart Package Management

- **Auto-detects package manager** - Uses `uv` if available (10-100x faster), falls back to `pip`
- **Handles compatibility** - Skips packages incompatible with your Python version
- **Filters intelligently**:
  - Excludes standard library modules (os, sys, base64, etc.)
  - Ignores custom/local packages
  - Only suggests real PyPI packages

## Troubleshooting

### Common Issues

**Q: "No kernel initialized" warning when using `<leader>jj`**
A: Press `<leader>jl` first to auto-initialize the kernel for the current file type.

**Q: Jupytext command not found**
A: Pyworks adds .venv/bin to PATH automatically. Run `:PyworksSetup` to install jupytext.

**Q: Images open in external viewer**
A: Fixed by default. Ensure you're using Kitty or Ghostty terminal.

**Q: Matplotlib opens external window**
A: Don't use `plt.show()`. Just create the plot and let Molten capture it.

### Debug Mode

Enable debug mode to see what's happening:

```lua
require("pyworks").setup({
  notifications = { debug_mode = true }
})
```

Or temporarily:
```vim
:lua vim.g.pyworks_debug = true
```

## Integration with Other Plugins

### Dependencies

| Plugin          | Purpose                        | Required           |
| --------------- | ------------------------------ | ------------------ |
| `molten-nvim`   | Code execution                 | Yes (for notebooks)|
| `image.nvim`    | Display plots inline           | Yes (for plots)    |

Note: pyworks.nvim handles .ipynb files directly using the jupytext CLI (automatically installed as a Python package). No separate jupytext.nvim plugin is required.

### Migrating from jupytext.nvim

If you previously used jupytext.nvim, pyworks now handles notebooks directly:

1. **Remove jupytext.nvim** from your plugin dependencies
2. Pyworks will auto-detect and warn if jupytext.nvim is still installed
3. If you prefer jupytext.nvim, set `skip_jupytext = true` in your pyworks config

### Works Well With

Optional plugins that enhance the experience:
- [quarto-nvim](https://github.com/quarto-dev/quarto-nvim) - Enhanced notebook features
- [otter.nvim](https://github.com/jmbuhr/otter.nvim) - LSP inside code cells

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- [molten-nvim](https://github.com/benlubas/molten-nvim) - Jupyter integration for Neovim
- [image.nvim](https://github.com/3rd/image.nvim) - Inline image rendering
- [jupytext](https://github.com/mwouts/jupytext) - Jupyter notebook conversion CLI
- [uv](https://github.com/astral-sh/uv) - Lightning-fast Python package management
