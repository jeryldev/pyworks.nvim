# Molten Quick Reference Card

## 🆕 What's New in Pyworks

- **Async Operations**: Setup and package installation no longer freeze Neovim
- **Smart Package Browser**: Interactive categories with descriptions
- **Auto Kernel Init**: Notebooks automatically initialize kernels
- **Progress Indicators**: Visual feedback for all operations
- **Better Error Handling**: Clear messages with recovery suggestions

## Pyworks Commands

- `:PyworksSetup` - Interactive setup with async venv creation
- `:PyworksWeb` - Quick setup for web development (FastAPI/Flask/Django)
- `:PyworksNewNotebook [filename] [language]` - Create notebook with auto kernel init
- `:PyworksCheckEnvironment` - Comprehensive diagnostics with actionable feedback
- `:PyworksInstallPackages <packages>` - Background package installation
- `:PyworksBrowsePackages` - Interactive package browser with search
- `:PyworksShowEnvironment` - Display Python environment status

### Short Aliases

- `:PWSetup` - Same as :PyworksSetup
- `:PWCheck` - Same as :PyworksCheckEnvironment
- `:PWInstall` - Same as :PyworksInstallPackages
- `:PWNewNotebook` - Same as :PyworksNewNotebook

## Getting Started

### For Data Science Projects

1. Run `:PyworksSetup` and choose "Data Science / Notebooks"
2. Create notebook: `:PyworksNewNotebook [filename]`
3. Initialize kernel: `<leader>ji`

### For Web Development

1. Run `:PyworksWeb` (or `:PyworksSetup` → choose "Web Development")
2. Start coding with FastAPI/Flask/Django

## Example Workflows

### Data Science Workflow

```bash
cd ~/projects/ml_analysis
nvim
# :PyworksSetup → Choose "Data Science"
# Restart nvim
# :PyworksNewNotebook analysis
# <leader>ji to initialize kernel
```

### Web Development Workflow

```bash
cd ~/projects/my_api
nvim
# :PyworksWeb
# Create main.py and start coding FastAPI
```

## Project Types in PyworksSetup

### 1. Data Science / Notebooks

- **Essential**: `pynvim`, `jupyter_client`, `ipykernel`, `jupytext`
- **Optional**: `numpy`, `pandas`, `matplotlib`, `seaborn`, `scikit-learn`, `scipy`, `statsmodels`, `plotly`, `tensorflow`, `torch`
- **Creates**: `.nvim.lua` for Molten integration

### 2. Web Development

- **Quick command**: `:PyworksWeb`
- **Packages**: `fastapi`, `uvicorn[standard]`, `flask`, `django`, `sqlalchemy`, `alembic`, `pydantic`, `requests`, `httpx`, `pytest`, `black`, `ruff`
- **No** `.nvim.lua` needed

### 3. General Python Development

- **Packages**: `pytest`, `black`, `ruff`, `mypy`, `ipython`, `python-dotenv`, `rich`, `typer`, `click`

### 4. Automation / Scripting

- **Packages**: `requests`, `beautifulsoup4`, `selenium`, `pandas`, `schedule`, `python-dotenv`, `rich`, `typer`

### 5. Custom

- Choose your own packages
- Decide if you need `.nvim.lua`

## Enhanced Features

- **Async Virtual Environment Creation** - Non-blocking setup with progress indicators
- **Background Package Installation** - Continue coding while packages install
- **Smart Package Browser** - Browse by category, search, or install entire collections
- **Auto Kernel Initialization** - Notebooks automatically set up Jupyter kernels
- **Intelligent Caching** - Reduced filesystem calls for better performance
- **Comprehensive Error Handling** - Clear messages with suggested fixes

## Virtual Environment Notes

- Works with both `uv venv` and `python -m venv` created environments
- Activation is the same: `source .venv/bin/activate`
- The setup automatically detects and uses `uv` for faster package installation when available

## What PyworksCheckEnvironment Shows

- Python host configuration status
- Virtual environment detection
- Installed packages (essential + data science)
- Molten command availability
- Remote plugin registration status

## Essential Commands

- `<leader>ji` - Initialize kernel (start here!)
- `<leader>js` - Show status/info (kernel, cells)
- `<leader>jl` - Evaluate current line (creates new cell)
- `<leader>jv` - Evaluate visual selection
- `<leader>je` - Evaluate with operator (e.g., `<leader>jei{` for inner block)

## Cell Navigation

- `]%` or `<leader>j]` - Next cell
- `[%` or `<leader>j[` - Previous cell
- `]j` - Next # %% cell marker
- `[j` - Previous # %% cell marker
- `<leader>jr` - Select current cell
- `vi%` - Visual select current cell (custom)

## Output Management

- `<leader>jo` - Open/enter output window
- `<leader>jh` - Hide output
- `<leader>jd` - Delete cell

## Image Management (Kitty/Ghostty)

- `<leader>jc` - Clear all images (fix overlap)
- `<leader>jC` - Clear images & re-run cell

## Working with Notebooks

- **Open .ipynb**: Just use `:e notebook.ipynb` (jupytext handles conversion)
- **Cell markers**: Use `# %%` in Python files to create cells
- **Save**: Normal `:w` (jupytext syncs automatically)

## Pro Tips

1. Always run `<leader>ji` first to initialize kernel
2. Use `<leader>js` to check kernel status
3. Create cells with `<leader>jl` or `<leader>jv`
4. For plots: Use `plt.close('all')` before new plots
5. Press `<leader>jc` if images overlap
6. Virtual text output shows inline by default
7. Output window is configured for 200x30 size

## Supported Languages

- Python (default)
- Julia (`:PyworksNewNotebook notebook julia`)
- R (`:PyworksNewNotebook notebook r`)
- Bash and others supported via kernel

## Troubleshooting

- **No kernel**: Run `<leader>ji` to initialize
- **Images overlap**: Use `<leader>jc` to clear
- **Can't see output**: Try `<leader>jo` to open window
- **Sync issues**: Save file (`:w`) to trigger jupytext sync
