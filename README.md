# 🚀 pyworks.nvim v3.0

**Zero-configuration multi-language support for Python, Julia, and R in Neovim**

A revolutionary Neovim plugin that provides automatic environment setup, package detection, and Jupyter-like code execution for Python, Julia, and R - with absolutely zero configuration required.

## ✨ Features

### Zero-Configuration Magic

- 🎯 **Just Open and Code** - No setup, no configuration, just start coding
- 🚀 **Auto-Everything** - Environment creation, package detection, kernel initialization
- 🔬 **True Multi-language** - Python, Julia, and R with identical workflows

### Core Capabilities

- 📝 **Notebook Creation Commands** - Create Python/Julia/R notebooks with templates instantly
- 📦 **Smart Package Detection** - Detects and installs missing packages automatically
- 📓 **Native Notebook Support** - Edit .ipynb files as naturally as .py files
- ⚡ **Molten Integration** - Execute code cells with Jupyter-like experience
- 🖼️ **Inline Plots** - Display matplotlib/Plots.jl/ggplot2 output directly in Neovim
- 🔄 **Dynamic Kernel Detection** - Finds available kernels automatically (no hardcoding)
- 🛡️ **Project-Based Activation** - Only runs in actual project directories
- 📔 **Automatic Metadata Fixing** - Handles notebook format issues seamlessly

## 📋 Requirements

- Neovim ≥ 0.9.0
- Python 3.8+

### For Notebook Support

- `jupytext` CLI - Required to open/edit .ipynb files
- **Automatically installed** by pyworks during any project setup

### Optional

- [`uv`](https://github.com/astral-sh/uv) - Faster package management (10-100x faster than pip)

## 📝 Typical Workflow

1. **Create a new notebook:**
   ```vim
   :PyworksNewPython analysis     " Creates analysis.py with cells
   " or
   :PyworksNewPythonNotebook data " Creates data.ipynb
   ```

2. **Write your code:**
   - Cells are marked with `# %%`
   - Add imports in first cell
   - Write analysis code in subsequent cells

3. **Execute code:**
   - `<leader>jv` - Run selected lines (visual mode)
   - `<leader>jl` - Run current line
   - `<leader>jr` - Select current cell
   - `<leader>jc` - Re-run current cell

4. **Navigate:**
   - `]j` - Next cell
   - `[j` - Previous cell
   - `<leader>jo` - Show output

5. **Package management:**
   - Missing packages detected automatically
   - `<leader>pi` - Install missing packages
   - `:PyworksInstallPython numpy pandas` - Install specific packages

## 🚀 Installation

### Complete Setup with [lazy.nvim](https://github.com/folke/lazy.nvim)

Create `~/.config/nvim/lua/plugins/pyworks.lua` with this **simplified configuration**:

> **LazyVim Users**: See [examples/lazyvim-setup.lua](examples/lazyvim-setup.lua) for LazyVim-specific configuration

```lua
return {
  {
    "jeryldev/pyworks.nvim",
    dependencies = {
      {
        "GCBallesteros/jupytext.nvim",
        config = true, -- This ensures jupytext.setup() is called!
      },
      "nvim-lua/plenary.nvim",      -- Required: Core utilities
      "benlubas/molten-nvim",       -- Required: Code execution
      "3rd/image.nvim",             -- Required: Image display
    },
    config = function()
      require("pyworks").setup({
        -- Pyworks auto-configures everything with proven settings!
        -- Just specify any preferences:
        python = {
          use_uv = true,  -- Use uv for faster package installation
        },
        image_backend = "kitty",  -- or "ueberzug" for other terminals

        -- Optional: Skip auto-configuration of specific dependencies
        -- skip_molten = false,
        -- skip_jupytext = false,
        -- skip_image = false,
        -- skip_keymaps = false,
      })
    end,
    lazy = false,    -- Load immediately for file detection
    priority = 100,  -- Load early
  },
}
```

### Why This Simple Configuration Works

**🎯 Auto-Configuration Magic**: Pyworks now handles ALL the complex setup automatically:

- **Project Detection**: Only activates in directories with `.venv`, `Project.toml`, etc.
- **Molten Setup**: Configures hover-based output with optimal window sizes
- **Jupytext Integration**: Handles PATH management and notebook conversion
- **Image Display**: Sets up plot rendering with terminal compatibility
- **Helper Keymaps**: Adds `<leader>ps` (status) and `<leader>pc` (clear cache)

**🔧 Four Complex Systems, One Simple Config**: Behind the scenes, pyworks coordinates:

1. **Pyworks Core**: Environment management for Python, Julia, and R
2. **Jupytext**: Notebook viewing/editing with intelligent PATH handling
3. **Molten**: Jupyter-like code execution with battle-tested output settings
4. **Image.nvim**: Plot and image display optimized for data science

**✅ Production-Tested Settings**: All auto-configuration uses proven settings refined through real-world usage - the same optimal configuration that powers seamless multi-language data science workflows.

**🚀 True Zero-Config**:

- Copy this 25-line config once
- Open any `.py`, `.jl`, `.R`, or `.ipynb` file
- Everything works automatically from the first file

The complex 240+ line configuration is now built into pyworks itself!

## 🎯 The Six Core Scenarios

Pyworks provides identical zero-configuration workflows for:

1. **Python Files (.py)** - Virtual environment, package detection, execution
2. **Julia Files (.jl)** - Project activation, package detection, execution
3. **R Files (.R)** - Environment setup, package detection, execution
4. **Python Notebooks (.ipynb)** - Auto-detects Python, converts, executes
5. **Julia Notebooks (.ipynb)** - Auto-detects Julia, converts, executes
6. **R Notebooks (.ipynb)** - Auto-detects R, converts, executes

## 🚀 What's New in v3.0

### Latest Updates (v3.0.1)
- **Enhanced Package Management**: New commands for Python package management
  - `:PyworksInstallPython` - Install packages with UV or pip
  - `:PyworksUninstallPython` - Remove packages cleanly  
  - `:PyworksListPython` - View all installed packages
- **Smart Package Detection**: Automatically filters out:
  - Standard library modules (base64, os, sys, etc.)
  - Custom/local packages (company-specific modules)
  - Only suggests real PyPI packages
- **Better Error Reporting**: Detailed error buffers for package installation failures
- **Per-Project Python**: Each project uses its own Python environment correctly
- **UV/pip Detection**: Correctly identifies and uses the right package manager

### Core v3.0 Features
- **True Zero-Config**: Just open files and start coding
- **Dynamic Kernel Detection**: Finds julia-1.11, not hardcoded "julia"
- **Project-Based Activation**: Only runs in actual project directories
- **Clean Architecture**: Modular design with core/languages/notebook separation
- **Better Notifications**: Silent when ready, informative when needed
- **⚡ Async Everything**: Non-blocking operations with progress indicators
- **🎯 Smart Caching**: Reduces system calls with intelligent 5-30 second TTL

## 📓 Jupyter Notebook Support

### 🎉 Automatic Essential Package Installation

When you open a `.ipynb` file or a Python file with Jupyter cells (`# %%`), pyworks automatically:

1. **Detects missing essential packages** - pynvim, ipykernel, jupyter_client, jupytext, ipython, notebook
2. **Auto-installs them without prompting** - These are non-negotiable requirements for notebook functionality
3. **Creates/fixes the project kernel** - Ensures your project has a working Jupyter kernel
4. **No manual intervention needed** - Just open the file and pyworks handles the rest!

This means you can clone any project with notebooks and start working immediately - pyworks ensures all the infrastructure is ready.

### 🔄 Intelligent Workflow

Pyworks provides automatic kernel initialization and package detection for all supported file types:

#### How It Works

When you open any supported file (.py, .jl, .R, .ipynb), pyworks:

1. **Detects the file type** and shows notifications (if Molten is available)
2. **Checks for a compatible kernel** in your Jupyter installation
3. **Auto-initializes the kernel** if found, or prompts for selection
4. **Scans for missing packages** (Python only currently)
5. **Offers one-click installation** with `<leader>pi`

#### Language-Specific Features

**Python Files (.py, .ipynb)**:

- Scans for imports and detects missing packages
- Checks compatibility (e.g., TensorFlow on Python 3.12+)
- Shows "Press `<leader>pi` to install" for missing packages
- Full package management with pip/uv

**Julia Files (.jl)**:

- Auto-initializes Julia kernel on file open
- Detects `using` and `import` statements
- Package management via Pkg.add() (integration coming soon)

**R Files (.R)**:

- Auto-initializes R kernel (IRkernel) on file open
- Detects `library()` and `require()` calls
- Package management via install.packages() (integration coming soon)

### 📦 Smart Package Management

#### Automatic Detection

- **Scans imports on file open** - Detects missing packages from `import` statements
- **Shows missing packages** - "📦 Missing packages: numpy, pandas, matplotlib"
- **Installation prompt** - ">>> Press <leader>pi to install missing packages"

#### Intelligent Installation

- **Auto-detects package manager** - Uses `uv` if available (10-100x faster), falls back to `pip`
- **Handles compatibility gracefully**:
  - Skips packages incompatible with your Python version
  - Suggests alternatives (e.g., PyTorch instead of TensorFlow for Python 3.12+)
  - Removes problematic version specifiers automatically
- **One-key installation** - Press `<leader>pi` to install all missing, compatible packages

#### Compatibility Handling

Pyworks knows about package compatibility issues:

- **TensorFlow** - Not compatible with Python 3.12+, suggests PyTorch or JAX
- **numba** - Limited Python 3.12 support, warns about potential issues
- **PyQt5** - Replaced by PyQt6 for newer Python versions

### Output Display

Pyworks uses Molten's enhanced popup window system for displaying cell outputs:

#### Window Configuration

- **Large floating windows** (40 lines tall, 150 chars wide) for plots and DataFrames
- **Auto-opens after execution** - Output appears automatically when you run cells
- **Smart border cropping** - Windows adjust to fit screen edges
- **Image support** - Full color plots and images (requires Kitty/Ghostty terminal)

#### Output Controls

- `<leader>jo` - Open/show output window
- `<leader>jh` - Hide output window
- `<leader>jd` - Delete/clear cell output
- `<leader>jc` - Clear all images

> **Tip**: Adjust window sizes in your config if needed for ultra-wide monitors or specific workflows.

### Terminal Requirements for Images

For image/plot display in notebooks, you need:

- **Kitty terminal** (recommended) - `brew install --cask kitty`
- **Ghostty terminal** (alternative) - Supports Kitty graphics protocol
- Other terminals will show text output only

### Kernel Requirements

For multi-language support, install the appropriate kernels:

**Python** (installed automatically by pyworks):

```bash
python -m pip install ipykernel
python -m ipykernel install --user --name myproject
```

**Julia**:

```julia
using Pkg
Pkg.add("IJulia")
```

**R**:

```r
install.packages('IRkernel')
IRkernel::installspec()
```

## 📚 Commands

### Core Commands

| Command | Description |
|---------|-------------|
| `:PyworksSetup` | Manually trigger environment setup for current file |
| `:PyworksStatus` | Show package status (imported/installed/missing) |
| `:PyworksInstall` | Install missing packages for current file |
| `:PyworksClearCache` | Clear all cached data |
| `:PyworksCacheStats` | Show cache statistics |
| `:PyworksDiagnostics` | Run diagnostics to check environment setup |

### Notebook Creation Commands

| Command | Description |
|---------|-------------|
| `:PyworksNewPython [name]` | Create new Python file with cell markers (.py) |
| `:PyworksNewJulia [name]` | Create new Julia file with cell markers (.jl) |
| `:PyworksNewR [name]` | Create new R file with cell markers (.R) |
| `:PyworksNewPythonNotebook [name]` | Create new Python Jupyter notebook (.ipynb) |
| `:PyworksNewJuliaNotebook [name]` | Create new Julia Jupyter notebook (.ipynb) |
| `:PyworksNewRNotebook [name]` | Create new R Jupyter notebook (.ipynb) |

### Python-Specific Commands

| Command | Description |
|---------|-------------|
| `:PyworksInstallPython <packages>` | Install specific Python packages |
| `:PyworksUninstallPython <packages>` | Uninstall Python packages |
| `:PyworksListPython` | List all installed Python packages |

### Keymaps

#### Pyworks Keymaps

| Keymap | Description |
|--------|-------------|
| `<leader>ps` | Show package status |
| `<leader>pc` | Clear cache |
| `<leader>pi` | Install missing packages (buffer-local) |

#### Molten (Code Execution) Keymaps

| Keymap | Mode | Description |
|--------|------|-------------|
| `<leader>jl` | Normal | Run current line |
| `<leader>jv` | Visual | Run selected lines |
| `<leader>jr` | Normal | Select current cell |
| `<leader>jc` | Normal | Re-evaluate current cell |
| `<leader>jd` | Normal | Delete cell output |
| `<leader>jo` | Normal | Show output window |
| `<leader>jh` | Normal | Hide output window |
| `<leader>je` | Normal | Enter output window |
| `]j` | Normal | Jump to next cell |
| `[j` | Normal | Jump to previous cell |
| `K` | Normal | Show output or LSP hover |

#### Molten Kernel Management

| Keymap | Description |
|--------|-------------|
| `<leader>mi` | Initialize kernel |
| `<leader>mr` | Restart kernel |
| `<leader>mx` | Interrupt execution |
| `<leader>mn` | Import notebook outputs |
| `<leader>ms` | Save outputs |

## 🎯 Quick Start

### Creating New Notebooks

```vim
" Create Python notebook with cells
:PyworksNewPython analysis
" → Created Python notebook: analysis.py

" Create Jupyter notebook
:PyworksNewPythonNotebook report
" → Created Python notebook: report.ipynb

" Create Julia/R files
:PyworksNewJulia experiment     " → experiment.jl
:PyworksNewR stats              " → stats.R
```

### Python Data Science

```vim
" Create and start coding immediately
:PyworksNewPython analysis
" → Created Python notebook: analysis.py
" → 🔍 Processing: analysis.py
" → 🐍 Python (analysis): Using .venv
" → ✅ Molten ready with python3 kernel

" Select code and run with <leader>jv
" Navigate cells with ]j and [j
```

### Julia Scientific Computing

```vim
:PyworksNewJulia experiment
" → Created Julia notebook: experiment.jl
" → 🔶 Julia (experiment): Using Project.toml
" → ✅ Molten ready with julia kernel
```

### R Statistical Analysis

```vim
:PyworksNewR analysis
" → Created R notebook: analysis.R
" → 📦 R (analysis): Using renv
" → ✅ Molten ready with ir kernel
```

## ⌨️ Keybindings

### Jupyter/Notebook Operations

| Keybinding   | Description                            | When Needed               |
| ------------ | -------------------------------------- | ------------------------- |
| `<leader>ji` | Initialize Jupyter kernel manually     | Rarely - auto-initializes |
| `<leader>jl` | Evaluate current line                  | Execute single line       |
| `<leader>jv` | Evaluate visual selection              | Execute selected code     |
| `<leader>jr` | Select current cell (visual selection) | Select notebook cell      |
| `<leader>je` | Evaluate operator                      | Execute with motion       |
| `<leader>jo` | Open output window                     | View hidden output        |
| `<leader>jh` | Hide output                            | Hide output window        |
| `<leader>jd` | Delete cell output                     | Clear cell results        |
| `<leader>js` | Show kernel status/info                | Check kernel state        |
| `<leader>jc` | Clear images                           | Remove displayed images   |

### Package Management

| Keybinding   | Description                                           |
| ------------ | ----------------------------------------------------- |
| `<leader>pi` | Install missing packages (auto-detected from imports) |
| `<leader>pa` | Manually analyze imports in current buffer            |

## 🛠️ Common Use Cases

### Data Science / Notebooks

- **Packages**: numpy, pandas, matplotlib, scikit-learn, jupyter
- **Features**: Full Jupyter integration with Molten
- **Quick Start**: Just open any `.py` or `.ipynb` file

### Web Development

- **Packages**: FastAPI, Flask, Django, SQLAlchemy, pytest, black, ruff
- **Quick Start**: `:PyworksInstallPython fastapi uvicorn sqlalchemy`

### Machine Learning

- **Packages**: torch, transformers, scikit-learn, xgboost
- **Quick Start**: `:PyworksInstallPython torch transformers`
- Decide if you need Jupyter integration

## 🔧 Configuration

### Default Settings (All Optional)

```lua
require("pyworks").setup({
  python = {
    preferred_venv_name = ".venv",
    use_uv = true,  -- 10-100x faster than pip
    auto_install_essentials = true,
    essentials = { "pynvim", "ipykernel", "jupyter_client", "jupytext" },
  },
  julia = {
    auto_install_ijulia = true,  -- Prompt once if missing
  },
  r = {
    auto_install_irkernel = true,  -- Prompt once if missing
  },
  notifications = {
    verbose_first_time = true,
    silent_when_ready = true,
    show_progress = true,
    debug_mode = false,
  },
})
```

## 🎮 How It Works

### The Zero-Configuration Experience

1. **Open any supported file** - pyworks detects file type
2. **Automatic setup** - Creates environment, installs essentials
3. **Package detection** - Scans imports, shows missing packages
4. **Kernel initialization** - Auto-starts appropriate kernel
5. **Ready to code** - Use keymaps to execute code immediately

### Project Detection

Pyworks only activates in directories containing:

- `.venv` (Python virtual environment)
- `Project.toml` (Julia project)
- `renv.lock` (R project)
- `requirements.txt`, `setup.py`, `pyproject.toml` (Python)
- `.Rproj` (RStudio project)

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

### Common Issues

**Q: Pyworks runs in all directories**
A: v3.0 only activates in project directories with markers (.venv, Project.toml, etc.)

**Q: "No visual selection found" with Molten**
A: Use `<leader>jr` to select cell, then `<leader>jv` while in visual mode

**Q: Julia kernel not found**
A: Julia kernels include version (julia-1.11). Install IJulia if missing.

**Q: Images open in external viewer**
A: Fixed in v3.0 with molten_auto_image_popup = false

**Q: Jupytext command not found**
A: Pyworks adds .venv/bin to PATH automatically. Install with pip if needed.

### Debug Mode

```lua
require("pyworks").setup({
  notifications = { debug_mode = true }
})
```

Or temporarily: `:lua vim.g.pyworks_debug = true`

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
