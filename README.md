# pyworks.nvim

**Zero-configuration Python development for Neovim with Jupyter-like notebook support**

A Neovim plugin that provides automatic environment setup, package detection, and code execution for Python projects - primarily focused on Python and Python notebooks.

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

> **Note**: While pyworks.nvim includes experimental support for Julia and R, the primary focus is on Python and Python notebooks.

## Requirements

- Neovim ≥ 0.9.0
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
      {
        "GCBallesteros/jupytext.nvim",
        config = true,
      },
      {
        "benlubas/molten-nvim",
        build = ":UpdateRemotePlugins",
      },
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
   - `<leader>jl` - Run current line
   - `<leader>jc` - Run current cell and move to next (Shift+Enter in Jupyter)
   - `<leader>je` - Re-run current cell

4. **Create new cells**:
   - `<leader>ja` - Insert code cell above
   - `<leader>jb` - Insert code cell below
   - `<leader>jma` - Insert markdown cell above

5. **Package management**:
   - Missing packages detected automatically
   - Press `<leader>pi` to install missing packages
   - Or use `:PyworksInstallPython numpy pandas matplotlib`

## Key Bindings

### Cell Execution

| Keymap       | Mode   | Description                      |
| ------------ | ------ | -------------------------------- |
| `<leader>jl` | Normal | Run current line                 |
| `<leader>jr` | Visual | Run selection                    |
| `<leader>jc` | Normal | Run current cell and move to next |
| `<leader>je` | Normal | Re-evaluate current cell (stay in place) |
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
| `<leader>jd` | Delete cell output       |
| `<leader>jh` | Hide output window       |
| `<leader>jo` | Enter output window      |
| `K`          | Show output or LSP hover |

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
| `<leader>jzc` | Collapse all cells             |
| `<leader>jze` | Expand all cells               |
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

> Note: Julia and R notebook creation commands are experimental.

### Environment Management

| Command               | Description                                  |
| --------------------- | -------------------------------------------- |
| `:PyworksSetup`       | Manually trigger environment setup           |
| `:PyworksStatus`      | Show package status (imports/installed/missing) |
| `:PyworksInstall`     | Install missing packages for current file    |
| `:PyworksClearCache`  | Clear all cached data                        |
| `:PyworksDiagnostics` | Run diagnostics to check environment setup   |

### Python Package Management

| Command                              | Description                  |
| ------------------------------------ | ---------------------------- |
| `:PyworksInstallPython <packages>`   | Install specific packages    |
| `:PyworksUninstallPython <packages>` | Uninstall packages           |
| `:PyworksListPython`                 | List all installed packages  |

## Configuration

### Default Settings (All Optional)

```lua
require("pyworks").setup({
  python = {
    preferred_venv_name = ".venv",
    use_uv = true,  -- 10-100x faster than pip
    auto_install_essentials = true,
    essentials = { "pynvim", "ipykernel", "jupyter_client", "jupytext" },
  },
  notifications = {
    verbose_first_time = true,
    silent_when_ready = true,
    show_progress = true,
    debug_mode = false,
  },
  -- Optional: Skip auto-configuration of specific dependencies
  skip_molten = false,
  skip_jupytext = false,
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

Pyworks only activates in directories containing:
- `.venv` (Python virtual environment)
- `requirements.txt`, `setup.py`, `pyproject.toml` (Python project markers)
- `Project.toml` (Julia - experimental)
- `renv.lock`, `.Rproj` (R - experimental)

### Smart Package Management

- **Auto-detects package manager** - Uses `uv` if available (10-100x faster), falls back to `pip`
- **Handles compatibility** - Skips packages incompatible with your Python version
- **Filters intelligently**:
  - Excludes standard library modules (os, sys, base64, etc.)
  - Ignores custom/local packages
  - Only suggests real PyPI packages

## Troubleshooting

### Common Issues

**Q: "No kernel initialized" warning when using `<leader>jc` or `<leader>je`**
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
| `jupytext.nvim` | Open/save .ipynb files         | Yes (for notebooks)|
| `image.nvim`    | Display plots inline           | Yes (for plots)    |

### Works Well With

Optional plugins that enhance the experience:
- [quarto-nvim](https://github.com/quarto-dev/quarto-nvim) - Enhanced notebook features
- [otter.nvim](https://github.com/jmbuhr/otter.nvim) - LSP inside code cells

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- [molten-nvim](https://github.com/benlubas/molten-nvim) - Jupyter integration for Neovim
- [jupytext.nvim](https://github.com/GCBallesteros/jupytext.nvim) - Seamless .ipynb file support
- [image.nvim](https://github.com/3rd/image.nvim) - Inline image rendering
- [uv](https://github.com/astral-sh/uv) - Lightning-fast Python package management
