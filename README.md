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
        -- Molten configuration for better image display
        vim.g.molten_image_provider = "image.nvim"
        vim.g.molten_output_win_max_height = 40  -- Increased for larger images
        vim.g.molten_output_win_max_width = 150  -- Allow wider output
        vim.g.molten_auto_open_output = true     -- Auto-show output
        vim.g.molten_output_crop_border = true   -- Better screen fit
      end,
    },
    {
      "3rd/image.nvim",
      opts = {
        backend = "kitty",  -- Requires Kitty or Ghostty terminal
        integrations = {},  -- Empty for Molten compatibility
        max_width = 150,    -- Match Molten's width
        max_height = 40,    -- Match Molten's height
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

### 🔄 Intelligent Workflow

When you open a notebook (.ipynb) or Python file, pyworks automatically:

1. **Detects file type** - Python, Julia, or R from notebook metadata
2. **Checks kernel availability** - Ensures project-specific kernel exists
3. **Auto-initializes kernel** - No need for manual `<leader>ji` in most cases
4. **Scans for imports** - Identifies all imported packages
5. **Checks installation status** - Compares against installed packages
6. **Shows smart notifications**:
   - Lists missing packages
   - Warns about incompatible packages (e.g., TensorFlow on Python 3.12+)
   - Suggests alternatives for incompatible packages
   - Shows hint: "Press `<leader>pi` to install compatible packages"

### 📦 Smart Package Management

- **Auto-detects package manager** - Uses `uv` if available (10-100x faster), falls back to `pip`
- **Handles compatibility gracefully**:
  - Skips packages incompatible with your Python version
  - Suggests alternatives (e.g., PyTorch instead of TensorFlow for Python 3.12+)
  - Attempts compatible versions when available
- **One-key installation** - Press `<leader>pi` to install all missing, compatible packages

### Output Display

Pyworks uses Molten's popup window system for displaying cell outputs with enhanced sizing:

- **Large floating windows** (40 lines tall, 150 chars wide) accommodate big plots and tables
- **Auto-opens after execution** - Output appears automatically when you run cells
- **Images and plots display clearly** in the enlarged popup (requires Kitty or Ghostty terminal)
- **Smart border cropping** - Windows fit nicely at screen edges
- Use `<leader>jo` to manually open output, `<leader>jh` to hide

> **Note**: The default configuration is optimized for data visualization. You can adjust window sizes in the Molten init function.

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
" Kernel auto-initializes, packages checked automatically
" If packages missing, press <leader>pi to install
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

| Keybinding   | Description                                          | When Needed                    |
| ------------ | ---------------------------------------------------- | ------------------------------ |
| `<leader>ji` | Initialize Jupyter kernel manually                  | Rarely - auto-initializes      |
| `<leader>jl` | Evaluate current line                               | Execute single line            |
| `<leader>jv` | Evaluate visual selection                           | Execute selected code          |
| `<leader>jr` | Select current cell (visual selection)              | Select notebook cell           |
| `<leader>je` | Evaluate operator                                   | Execute with motion            |
| `<leader>jo` | Open output window                                  | View hidden output             |
| `<leader>jh` | Hide output                                         | Hide output window             |
| `<leader>jd` | Delete cell output                                  | Clear cell results             |
| `<leader>js` | Show kernel status/info                             | Check kernel state             |
| `<leader>jc` | Clear images                                         | Remove displayed images        |

### Package Management

| Keybinding   | Description                                          |
| ------------ | ---------------------------------------------------- |
| `<leader>pi` | Install missing packages (auto-detected from imports) |
| `<leader>pa` | Manually analyze imports in current buffer          |

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

### Pyworks Configuration

```lua
require("pyworks").setup({
  -- Python environment settings
  python = {
    preferred_venv_name = ".venv",  -- Virtual environment folder name
    use_uv = true,                  -- Prefer uv over pip when available
  },
  
  auto_activate_venv = true,  -- Auto-activate in terminals
  
  -- UI settings (optional)
  ui = {
    icons = {
      python = "🐍",
      success = "✓",
      error = "✗",
      warning = "⚠️",
    },
  },
})
```

### Customizing Output Window Size

If you need different output window dimensions (e.g., for ultra-wide monitors or specific workflows):

```lua
-- In your Molten plugin configuration:
init = function()
  vim.g.molten_output_win_max_height = 60  -- Even taller for huge plots
  vim.g.molten_output_win_max_width = 200  -- Wider for large DataFrames
end

-- And match in image.nvim:
opts = {
  max_width = 200,   -- Match Molten's width
  max_height = 60,   -- Match Molten's height
  -- ... other settings
}
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
- Check if `uv` is installed for faster operations (10-100x faster than pip)
- Use `:PyworksDebug` to see package manager details
- Pyworks automatically detects and uses `uv` if available, otherwise falls back to `pip`

### Package Compatibility Issues

Pyworks intelligently handles incompatible packages:

- **Python 3.12+ with TensorFlow**: Warns about compatibility, suggests PyTorch or JAX
- **Automatic alternatives**: Suggests compatible alternatives for problematic packages
- **Smart skipping**: Won't attempt to install packages that will fail
- **Version detection**: Checks your Python version before installation

Example: If you're on Python 3.12 and import TensorFlow:
```
⚠️ TensorFlow: Limited support for Python 3.12+
  Consider alternatives: torch, jax
```

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
