# 🐍 pyworks.nvim

**Python environments tailored for Neovim**

A comprehensive Python project management plugin for Neovim that handles virtual environments, package installation, and Jupyter notebook integration - all without leaving your editor.

## ✨ Features

- 🚀 **Async Project Setup** - Non-blocking virtual environment creation and package installation
- 📦 **Smart Package Browser** - Interactive package browser with categories and descriptions
- 📓 **Seamless Jupyter Support** - Edit .ipynb files as Python code with automatic conversion
- 🔍 **Real-time Diagnostics** - Environment health checks with actionable feedback
- 🎯 **Project Templates** - Pre-configured setups for data science, web development, and more
- ⚡ **Auto-activation** - Automatically activates virtual environments in Neovim terminals
- 🔄 **Progress Indicators** - Visual feedback for all long-running operations
- 🛡️ **Robust Error Handling** - Clear error messages with recovery suggestions
- 📔 **Smart Notebook Handling** - Automatic metadata fixing and format conversion

## 📋 Requirements

- Neovim ≥ 0.9.0
- Python 3.8+

### For Notebook Support
- `jupytext` CLI - Required to open/edit .ipynb files
- **Automatically installed** by pyworks during any project setup

### Optional
- [`uv`](https://github.com/astral-sh/uv) - Faster package management (10-100x faster than pip)

## 🚀 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "jeryldev/pyworks.nvim",
  dependencies = {
    -- Jupyter notebook file support (automatically configured)
    "GCBallesteros/jupytext.nvim",  -- For .ipynb file support
    
    -- Required for notebook execution
    {
      "benlubas/molten-nvim",
      version = "^1.0.0",
      build = ":UpdateRemotePlugins",
      init = function()
        -- Minimal Molten configuration for image support
        vim.g.molten_image_provider = "image.nvim"
        vim.g.molten_output_win_max_height = 20
      end,
    },
    {
      "3rd/image.nvim",
      opts = {
        backend = "kitty",  -- Requires Kitty or Ghostty terminal
        integrations = {},  -- Empty for Molten compatibility
        max_width = 100,
        max_height = 12,
        max_height_window_percentage = math.huge,
        max_width_window_percentage = math.huge,
        window_overlap_clear_enabled = true,
        window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
      },
    },
  },
  lazy = false,  -- Load immediately for autocmds
  config = function()
    require("pyworks").setup({
      -- Configuration options (optional)
      python = {
        preferred_venv_name = ".venv",
        use_uv = true,  -- Use uv when available
      },
      auto_activate_venv = true,
    })
  end,
}
```

## 🆕 What's New

### Performance & UX Improvements

- **Async Everything**: Virtual environment creation and package installation no longer freeze Neovim
- **Smart Package Browser**: Browse packages by category with descriptions, search, or install entire categories
- **Better Notifications**: Progress indicators show exactly what's happening with timing information
- **Auto Kernel Init**: Creating a Python notebook automatically initializes the Jupyter kernel

### Code Quality

- **Centralized Configuration**: Better state management and configuration validation
- **Robust Error Handling**: No more crashes - clear error messages with recovery suggestions
- **Performance Caching**: Reduced filesystem calls with intelligent caching
- **Code Deduplication**: Shared utilities module for consistent behavior

## 📓 Jupyter Notebook Support

### Output Display

Pyworks uses Molten's default popup window behavior for displaying cell outputs:

- **Cell outputs appear in floating windows** when you hover over executed cells
- **Images and plots display in the popup** (requires Kitty or Ghostty terminal)
- **Tables and text output** show in the floating window
- Use `<leader>jo` to manually open output, `<leader>jh` to hide

> **Note**: Inline virtual text display for outputs is currently not supported due to Molten limitations with image rendering.

### Terminal Requirements for Images

For image/plot display in notebooks, you need:
- **Kitty terminal** (recommended) - `brew install --cask kitty`
- **Ghostty terminal** (alternative) - Supports Kitty graphics protocol
- Other terminals will show text output only

## 🎯 Quick Start

### Data Science Project

```vim
:PyworksSetup    " Choose 'Data Science / Notebooks'
:PyworksNewNotebook analysis.ipynb
<leader>ji       " Initialize Jupyter kernel (auto-detects project kernel)
```

### Web Development Project

```vim
:PyworksWeb      " Quick setup for FastAPI/Flask/Django
" Start coding your API!
```

## 🎬 Demonstrations

### Setup and Usage

_Video demonstration of pyworks.nvim setup process and basic commands_

[![Setup Demo](https://img.youtube.com/vi/hoxrN8Qrbt4/maxresdefault.jpg)](https://www.youtube.com/watch?v=hoxrN8Qrbt4)

**What you'll see:**

- Running `:PyworksSetup` and choosing project type
- Virtual environment creation with automatic package installation
- Python host configuration and PATH setup
- Creating notebooks with `:PyworksNewNotebook`

### Notebook Workflow

_Video demonstration of Jupyter notebook workflow with Molten integration_

[![Notebook Workflow Demo](https://img.youtube.com/vi/D_y4YkZqGRY/maxresdefault.jpg)](https://www.youtube.com/watch?v=D_y4YkZqGRY)

**What you'll see:**

- Cell navigation with `]j` and `[j` (next/previous cell)
- Selecting cells with `<leader>jr` (select current cell)
- Running selections with `<leader>jv` (run visual selection)
- Chart generation with matplotlib, seaborn, and plotly
- Real-time output display and image rendering

## 📚 Commands

### Core Commands

| Command                                     | Description                                     |
| ------------------------------------------- | ----------------------------------------------- |
| `:PyworksSetup`                             | Interactive project setup with async operations |
| `:PyworksCheckEnvironment`                  | Show comprehensive environment diagnostics      |
| `:PyworksInstallPackages <packages>`        | Install packages in background (non-blocking)   |
| `:PyworksNewNotebook <filename> [language]` | Create notebook with auto kernel initialization |
| `:PyworksFixNotebook [filename]`            | Fix notebook missing Python metadata            |
| `:PyworksDebug`                             | Debug configuration and fix common issues       |
| `:PyworksShowEnvironment`                   | Display current Python environment status       |
| `:PyworksBrowsePackages`                    | Interactive package browser with categories     |

### Quick Setup Commands

| Command        | Description               |
| -------------- | ------------------------- |
| `:PyworksWeb`  | Setup for web development |
| `:PyworksData` | Setup for data science    |

### Short Aliases

| Alias            | Full Command               |
| ---------------- | -------------------------- |
| `:PWSetup`       | `:PyworksSetup`            |
| `:PWCheck`       | `:PyworksCheckEnvironment` |
| `:PWInstall`     | `:PyworksInstallPackages`  |
| `:PWNewNotebook` | `:PyworksNewNotebook`      |

## ⌨️ Keybindings

### Jupyter/Notebook Operations

| Keybinding   | Description                                          |
| ------------ | ---------------------------------------------------- |
| `<leader>ji` | Initialize Jupyter kernel                           |
| `<leader>jl` | Evaluate current line                               |
| `<leader>jv` | Evaluate visual selection                           |
| `<leader>jr` | Select current cell (visual selection)              |
| `<leader>je` | Evaluate operator                                   |
| `<leader>jo` | Open output window                                  |
| `<leader>jh` | Hide output                                         |
| `<leader>jd` | Delete cell output                                  |
| `<leader>js` | Show kernel status/info                             |
| `<leader>jc` | Clear images                                         |

### Package Management

| Keybinding   | Description                                          |
| ------------ | ---------------------------------------------------- |
| `<leader>pi` | Install suggested packages (from import detection)  |
| `<leader>pa` | Analyze imports in current buffer                   |

## 🛠️ Project Types

### 1. Data Science / Notebooks

- **Packages**: numpy, pandas, matplotlib, scikit-learn, jupyter, and more
- **Features**: Full Jupyter integration with Molten
- **Auto-configures**: Python host and PATH for notebooks

### 2. Web Development

- **Packages**: FastAPI, Flask, Django, SQLAlchemy, pytest, black, ruff
- **Quick Start**: `:PyworksWeb`

### 3. General Python Development

- **Packages**: pytest, black, ruff, mypy, ipython, rich, typer

### 4. Automation / Scripting

- **Packages**: requests, beautifulsoup4, selenium, schedule

### 5. Custom

- Choose your own packages
- Decide if you need Jupyter integration

## 🔧 Configuration

### Full Configuration Options

```lua
require("pyworks").setup({
  -- Python environment settings
  python = {
    preferred_venv_name = ".venv",  -- Virtual environment folder name
    use_uv = true,                  -- Prefer uv over pip when available
  },
  
  -- Molten/Jupyter output configuration (NEW!)
  molten = {
    virt_text_output = false,      -- false = show output in window below cell
    output_virt_lines = false,      -- false = don't use virtual lines
    virt_lines_off_by_1 = false,    -- false = output directly below cell
    output_win_max_height = 30,     -- Maximum height of output window
    auto_open_output = true,        -- Automatically show output after execution
    output_win_style = "minimal",   -- Window style: "minimal" or "none"
  },
  
  ui = {
    icons = {
      python = "🐍",
      success = "✓",
      error = "✗",
      warning = "⚠️",
    },
  },
  
  auto_activate_venv = true,  -- Auto-activate in terminals
})
```

## 🎮 Usage Examples

### Starting a New ML Project

```bash
mkdir my_ml_project
cd my_ml_project
nvim
```

```vim
:PyworksSetup
" Select: Data Science / Notebooks
" Restart Neovim after setup
:PyworksNewNotebook exploration.ipynb
```

### Installing Additional Packages

```vim
:PyworksInstallPackages scikit-learn xgboost lightgbm
" Or browse available packages:
:PyworksBrowsePackages
```

### Checking Your Environment

```vim
:PyworksCheckEnvironment
" Shows:
" - Python version and path
" - Virtual environment status
" - Installed packages
" - Jupyter/Molten integration status
```

## 🤝 Integration with Other Plugins

### Molten (Jupyter Notebooks)

pyworks.nvim automatically configures Molten when you choose a data science project type. After setup:

- `<leader>ji` - Initialize kernel
- `<leader>jl` - Run current line
- `<leader>jr` - Select current cell
- `<leader>jv` - Run visual selection
- `[j` / `]j` - Navigate between cells
- See all keybindings in `docs/molten_quick_reference.md`

### Dependencies Explained

| Plugin          | Purpose                                    | Required               |
| --------------- | ------------------------------------------ | ---------------------- |
| `molten-nvim`   | Jupyter kernel management & cell execution | Yes (for notebooks)    |
| `jupytext.nvim` | Open/save .ipynb files                     | Yes (for notebooks)    |
| `image.nvim`    | Display plots and images inline            | Yes (for data science) |

### Works Well With

While not required, these plugins enhance the notebook experience:

- [quarto-nvim](https://github.com/quarto-dev/quarto-nvim) - Enhanced notebook features and `.qmd` file support
- [otter.nvim](https://github.com/jmbuhr/otter.nvim) - LSP features inside code cells (requires quarto-nvim)

To add these optional enhancements, add this to your Neovim config:

```lua
{
  "quarto-dev/quarto-nvim",
  dependencies = {
    "jmbuhr/otter.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  ft = { "quarto", "markdown" },
  opts = {
    lspFeatures = {
      enabled = true,
      languages = { "r", "python", "julia", "bash", "html" },
      diagnostics = { enabled = true, triggers = { "BufWritePost" } },
      completion = { enabled = true },
    },
    codeRunner = {
      enabled = true,
      default_method = "molten",
    },
  },
}
```

### LazyVim

Fully compatible with LazyVim distributions. Just add to your plugins spec!

## 🐛 Troubleshooting

### Virtual Environment Not Detected

```vim
:PyworksDebug             " Debug configuration and fix issues
:PyworksCheckEnvironment  " Check current status
:PyworksShowEnvironment   " Detailed environment info
```

### Packages Not Installing

- Ensure you have a virtual environment: `:PyworksSetup`
- Check if `uv` is installed for faster operations
- Use `:PyworksDebug` to see package manager details

### Notebook Support

pyworks.nvim handles Jupyter notebooks seamlessly:

- **Automatic conversion**: Notebooks are converted to Python percent format for editing
- **Automatic metadata fixing**: Missing Python metadata is added automatically
- **Save support**: Changes are saved back to the original .ipynb format

If a notebook doesn't open correctly:

```vim
:PyworksFixNotebook       " Fix current notebook
:PyworksFixNotebook path/to/notebook.ipynb  " Fix specific notebook
```

- Ensure your virtual environment is activated
- Check if `uv` is installed for faster installs
- Use `:messages` to see installation progress

### Jupyter Notebooks Not Working

- Run `:PyworksDebug` to check jupytext and Python host configuration
- Run `:PyworksCheckEnvironment` to verify Molten is registered
- Ensure you selected "Data Science" project type
- Restart Neovim after initial setup

### Python Host Configuration Issues

- Run `:PyworksDebug` to see current configuration
- The command will automatically fix PATH and Python host if needed
- pyworks now loads immediately on startup to ensure proper configuration

## 📝 License

MIT License - see [LICENSE](LICENSE) for details

## 🙏 Acknowledgments

- Built for the Neovim community
- Inspired by various Python workflow tools
- Special thanks to these amazing projects:
  - [molten-nvim](https://github.com/benlubas/molten-nvim) - For bringing Jupyter's power to Neovim
  - [jupytext.nvim](https://github.com/GCBallesteros/jupytext.nvim) - For seamless .ipynb file support
  - [image.nvim](https://github.com/3rd/image.nvim) - For inline image rendering
  - [uv](https://github.com/astral-sh/uv) - For lightning-fast Python package management

---

Made with ❤️ for Python developers using Neovim
