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
    config = function()
      require("pyworks").setup()  -- See Configuration section for options
    end,
    lazy = false,
  },
}
```

Dependencies (`jeryldev/molten-nvim`, `jeryldev/image.nvim`) are declared in pyworks' `lazy.lua` and installed automatically.

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
| `<leader>jk` | Normal | Run cell without moving cursor (stay in place) |
| `<leader>jR` | Normal | Run all cells sequentially (waits for each) |

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

### Cell Operation Commands

For `skip_keymaps` users who prefer command-based workflows:

| Command                    | Description                          |
| -------------------------- | ------------------------------------ |
| `:PyworksNextCell`         | Move to next cell                    |
| `:PyworksPrevCell`         | Move to previous cell                |
| `:PyworksInsertCellAbove`  | Insert code cell above               |
| `:PyworksInsertCellBelow`  | Insert code cell below               |
| `:PyworksToggleCellType`   | Toggle cell type (code/markdown)     |
| `:PyworksMergeCellBelow`   | Merge with cell below                |
| `:PyworksSplitCell`        | Split cell at cursor                 |

## Commands

### Notebook Creation

| Command                            | Description                        |
| ---------------------------------- | ---------------------------------- |
| `:PyworksNewPython [name]`         | Create Python file with cells      |
| `:PyworksNewPythonNotebook [name]` | Create Python Jupyter notebook     |

### Environment Management

| Command                  | Description                                     |
| ------------------------ | ----------------------------------------------- |
| `:PyworksSetup`          | Create venv and install essential packages      |
| `:PyworksStatus`         | Show package status (imports/installed/missing) |
| `:PyworksDiagnostics`    | Run diagnostics (environment, plugins, cache)   |
| `:PyworksHelp`           | Show all commands and keymaps                   |
| `:PyworksReloadNotebook` | Reload notebook (useful after session restore)  |

### Package Management

| Command                     | Description                              |
| --------------------------- | ---------------------------------------- |
| `:PyworksSync`              | Install missing packages from imports    |
| `:PyworksAdd <packages>`    | Add packages to venv                     |
| `:PyworksRemove <packages>` | Remove packages from venv                |
| `:PyworksList`              | List all installed packages              |

## Configuration

All settings are optional. Here are the available options with their defaults:

```lua
require("pyworks").setup({
  -- Python environment settings
  python = {
    use_uv = true,                -- Use uv for faster package management (10-100x faster than pip)
    preferred_venv_name = ".venv",
    auto_install_essentials = true,
    essentials = { "pynvim", "ipykernel", "jupyter_client", "jupytext", "numpy", "pandas", "matplotlib" },
  },

  -- Package detection settings
  packages = {
    -- Patterns for detecting custom/local packages (won't suggest installing these)
    custom_package_prefixes = {
      "^my_", "^custom_", "^local_", "^internal_", "^private_",
      "^app_", "^lib_", "^src$", "^utils$", "^helpers$",
    },
  },

  -- Cache TTL in seconds
  cache = {
    kernel_list = 60,
    installed_packages = 300,
  },

  -- Notification settings
  notifications = {
    verbose_first_time = true,
    silent_when_ready = true,
    show_progress = true,
    debug_mode = false,
  },

  -- Cell delimiter pattern (e.g. "# COMMAND ----------" for Databricks)
  cell_marker = "# %%",

  -- Auto-detection
  auto_detect = true,  -- Automatically detect and setup on file open

  -- Image rendering (for inline plots)
  image_backend = "kitty",  -- "kitty" or "ueberzug"

  -- Skip auto-configuration of specific features (all default to false)
  skip_molten = false,    -- Skip Molten configuration
  skip_jupytext = false,  -- Skip jupytext setup (set true if using jupytext.nvim)
  skip_image = false,     -- Skip image.nvim configuration
  skip_keymaps = false,   -- Skip keymap setup (define your own)
})
```

## How It Works

### Zero-Configuration Experience

1. **Open any Python file** - pyworks detects file type
2. **Automatic setup** - Creates environment, installs essentials
3. **Package detection** - Scans imports, shows missing packages
4. **Kernel initialization** - Auto-starts Python kernel
5. **Ready to code** - Use keymaps to execute code immediately

### Molten Fork

Pyworks uses a maintained fork ([jeryldev/molten-nvim](https://github.com/jeryldev/molten-nvim)) that includes bug fixes for dict iteration safety and MoltenTick reentrancy, baked directly into the source. No runtime patching is needed.

### Project Detection

Pyworks finds your project root by looking for these markers (in priority order):
- `.venv` - Virtual environment (highest priority)
- `pyproject.toml`, `setup.py`, `requirements.txt` - Python project files
- `manage.py`, `app.py`, `main.py` - Framework entry points (Django, Flask, FastAPI)
- `Pipfile`, `poetry.lock`, `uv.lock` - Package manager lock files
- `conda.yaml`, `environment.yml` - Conda environments
- `dvc.yaml`, `mlflow.yaml` - ML pipeline configs
- `.git` - Git repository (lowest priority fallback)

For virtual environment detection, pyworks also respects environment variables:
- Local `.venv` directory (highest priority)
- `$VIRTUAL_ENV` environment variable
- `$CONDA_PREFIX` environment variable
- Fallback to creating a new `.venv`

### Smart Package Management

- **Auto-detects package manager** - Uses `uv` if available (10-100x faster), falls back to `pip`
- **Handles compatibility** - Skips packages incompatible with your Python version
- **Filters intelligently**:
  - Excludes standard library modules (os, sys, base64, etc.)
  - Ignores custom/local packages
  - Only suggests real PyPI packages

## Architecture

```
plugin/pyworks.lua          Entry point: autocmds (FileType, BufWinEnter, SessionLoadPost)
  └── lua/pyworks/
      ├── init.lua           Setup, user commands, configuration
      ├── dependencies.lua   Dependency checks
      ├── keymaps.lua        Cell execution, navigation, kernel management
      ├── ui.lua             Cell numbering, folding, floating windows
      ├── utils.lua          Project root detection, venv paths, system calls
      ├── core/
      │   ├── detector.lua       File routing, kernel auto-init
      │   ├── packages.lua       Import scanning, missing package detection
      │   ├── cache.lua          TTL-based in-memory cache
      │   ├── state.lua          Persistent state (JSON on disk)
      │   ├── notifications.lua  Deduped user notifications
      │   └── recursion_guard.lua  Prevents reload loops
      ├── languages/
      │   └── python.lua     Venv management, pip/uv commands, package ops
      ├── notebook/
      │   └── jupytext.lua   .ipynb read/write via jupytext CLI
      └── commands/
          └── create.lua     :PyworksNewPython, :PyworksNewPythonNotebook
```

### Startup Flow

1. `plugin/pyworks.lua` registers `FileType python` autocmd
2. On first Python file open: `require("pyworks").setup()` runs
3. `dependencies.setup()` defers (100ms) to check molten-nvim, image.nvim
4. `detector.on_file_open()` routes to Python handler
5. Python handler: setup venv, detect packages, auto-init Molten kernel

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

**Q: Notebook appears blank after session restore**
A: Run `:PyworksReloadNotebook` to reload with jupytext conversion.

**Q: E132 "Function call depth" error or notebook won't reload**
A: Run `:PyworksResetReloadGuard` to reset the reload guard, then retry.

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

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- [molten-nvim](https://github.com/jeryldev/molten-nvim) - Jupyter integration for Neovim (fork of [benlubas/molten-nvim](https://github.com/benlubas/molten-nvim) with bug fixes)
- [image.nvim](https://github.com/jeryldev/image.nvim) - Inline image rendering (fork of [3rd/image.nvim](https://github.com/3rd/image.nvim))
- [jupytext](https://github.com/mwouts/jupytext) - Jupyter notebook conversion CLI
- [uv](https://github.com/astral-sh/uv) - Lightning-fast Python package management
