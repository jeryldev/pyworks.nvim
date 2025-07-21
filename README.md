# 🐍 pyworks.nvim

**Python environments tailored for Neovim**

A comprehensive Python project management plugin for Neovim that handles virtual environments, package installation, and Jupyter notebook integration - all without leaving your editor.

## ✨ Features

- 🚀 **Smart Project Setup** - Automatically detects and creates virtual environments using `uv` or `python -m venv`
- 📦 **Package Management** - Install packages in the background while you keep coding
- 📓 **Jupyter Integration** - Create and work with Jupyter notebooks (Python, Julia, R)
- 🔍 **Environment Diagnostics** - Check Python setup, installed packages, and potential issues
- 🎯 **Project Templates** - Pre-configured setups for data science, web development, and more
- ⚡ **Auto-activation** - Automatically activates virtual environments in Neovim terminals

## 📋 Requirements

- Neovim ≥ 0.9.0
- Python 3.8+
- Optional but recommended:
  - [`uv`](https://github.com/astral-sh/uv) for faster package management
  - [`quarto-nvim`](https://github.com/quarto-dev/quarto-nvim) for enhanced notebook features (optional)

## 🚀 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "jeryldev/pyworks.nvim",
  dependencies = {
    -- Required for notebook support
    {
      "benlubas/molten-nvim",
      version = "^1.0.0",
      build = ":UpdateRemotePlugins",
    },
    "3rd/image.nvim",              -- For inline plots/images
    "GCBallesteros/jupytext.nvim",  -- For .ipynb file support

    -- Optional but recommended
    {
      "quarto-dev/quarto-nvim",   -- Enhanced notebook features
      dependencies = {
        "jmbuhr/otter.nvim",      -- LSP features in code blocks
        "nvim-treesitter/nvim-treesitter",
      },
    },
  },
  ft = { "python", "ipynb", "quarto", "markdown" },
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

## 🎯 Quick Start

### Data Science Project

```vim
:PyworksSetup    " Choose 'Data Science / Notebooks'
:PyworksNewNotebook analysis.ipynb
<leader>ji       " Initialize Jupyter kernel
```

### Web Development Project

```vim
:PyworksWeb      " Quick setup for FastAPI/Flask/Django
" Start coding your API!
```

## 📚 Commands

### Core Commands

| Command                                     | Description                             |
| ------------------------------------------- | --------------------------------------- |
| `:PyworksSetup`                             | Interactive project setup (choose type) |
| `:PyworksCheckEnvironment`                  | Show environment diagnostics            |
| `:PyworksInstallPackages <packages>`        | Install Python packages                 |
| `:PyworksNewNotebook [filename] [language]` | Create Jupyter notebook                 |
| `:PyworksShowEnvironment`                   | Show environment status                 |
| `:PyworksBrowsePackages`                    | Browse common packages                  |

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

## 🛠️ Project Types

### 1. Data Science / Notebooks

- **Packages**: numpy, pandas, matplotlib, scikit-learn, jupyter, and more
- **Features**: Full Jupyter integration with Molten
- **Creates**: `.nvim.lua` for proper Python host configuration

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

```lua
require("pyworks").setup({
  python = {
    preferred_venv_name = ".venv",  -- Virtual environment folder name
    use_uv = true,                  -- Prefer uv over pip when available
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
  create_nvim_lua = {         -- When to create .nvim.lua
    data_science = true,
    web = false,
    general = false,
    automation = false,
  },
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
- `<leader>jv` - Run visual selection
- `<leader>jr` - Select current cell
- `[j` / `]j` - Navigate between cells
- See all keybindings in `doc/molten_quick_reference.md`

### Dependencies Explained

| Plugin          | Purpose                                    | Required                 |
| --------------- | ------------------------------------------ | ------------------------ |
| `molten-nvim`   | Jupyter kernel management & cell execution | Yes (for notebooks)      |
| `jupytext.nvim` | Open/save .ipynb files                     | Yes (for notebooks)      |
| `image.nvim`    | Display plots and images inline            | Yes (for data science)   |
| `quarto-nvim`   | Enhanced notebook features, LSP in cells   | Optional but recommended |
| `otter.nvim`    | LSP support inside code blocks             | Optional (with quarto)   |

### LazyVim

Fully compatible with LazyVim distributions. Just add to your plugins spec!

## 🐛 Troubleshooting

### Virtual Environment Not Detected

```vim
:PyworksCheckEnvironment  " Check current status
:PyworksShowEnvironment   " Detailed environment info
```

### Packages Not Installing

- Ensure your virtual environment is activated
- Check if `uv` is installed for faster installs
- Use `:messages` to see installation progress

### Jupyter Notebooks Not Working

- Run `:PyworksCheckEnvironment` to verify Molten is registered
- Ensure you selected "Data Science" project type
- Restart Neovim after initial setup

## 📝 License

MIT License - see [LICENSE](LICENSE) for details

## 🙏 Acknowledgments

- Built for the Neovim community
- Inspired by various Python workflow tools
- Special thanks to [molten-nvim](https://github.com/benlubas/molten-nvim) for excellent Jupyter integration

---

Made with ❤️ for Python developers using Neovim
