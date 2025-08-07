# Pyworks.nvim Workflow Documentation

## Current Implementation Status

### 🎯 What Actually Happens When You Open Files

#### Python Files (.py)
1. **Immediate notification**: "Detected Python file - checking for Jupyter support..."
2. **Molten check**: If not available, shows "Molten not available - install with :PyworksSetup"
3. **Kernel check**: "Checking for compatible Python kernel..."
4. **Kernel initialization**: Auto-initializes or shows selection dialog
5. **Package detection**: Scans imports and shows missing packages
6. **Installation prompt**: "Press <leader>pi to install missing packages"

#### Jupyter Notebooks (.ipynb)
1. **Pre-processing**: Fixes missing metadata before file loads
2. **Kernel detection**: "Detected notebook - checking for compatible kernel..."
3. **Auto-initialization**: Starts appropriate kernel based on notebook language
4. **Package detection**: For Python notebooks, shows missing packages

#### Julia Files (.jl)
1. **Immediate notification**: "Detected Julia file - checking for Jupyter support..."
2. **Kernel initialization**: Auto-starts Julia kernel if available
3. **Future feature**: Package detection coming soon

#### R Files (.R)
1. **Immediate notification**: "Detected R file - checking for Jupyter support..."
2. **Kernel initialization**: Auto-starts R kernel (IRkernel) if available
3. **Future feature**: Package detection coming soon

## 🔧 Troubleshooting the Workflow

### If notifications aren't showing:

1. **Check Molten status**:
```vim
:echo exists(':MoltenInit')
" Should return 2 if Molten is loaded
```

2. **Check Python host**:
```vim
:echo g:python3_host_prog
" Should show path to Python with pynvim
```

3. **Manual test**:
```vim
:lua require("pyworks.molten").init_kernel()
" Should trigger the workflow manually
```

### Common Issues and Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| No notifications | Molten not loaded | Run `:PyworksSetup`, choose "Data Science", restart |
| Python host error | Missing pynvim | Pyworks auto-installs, just restart Neovim |
| Kernel not found | Jupyter not installed | Run `:PyworksSetup` to install |
| Package detection not working | Installation in progress | Wait for completion, tracked via job system |

## 📦 Package Detection Features

### What's Working:
- ✅ Detects missing packages from imports
- ✅ Handles package name mappings (PIL → Pillow)
- ✅ Normalizes incorrect names (matplotlib-pyplot → matplotlib)
- ✅ Checks Python version compatibility
- ✅ Suggests alternatives for incompatible packages
- ✅ Prevents duplicate notifications during installation

### Known Limitations:
- Only works for Python files currently
- Julia and R package detection planned for future
- Some complex import patterns may not be detected

## 🚀 Behind the Scenes

### Autocmd Flow:
1. `BufReadPost` triggers on file open
2. Immediate notification (no delay)
3. Deferred initialization (1 second delay for Molten to load)
4. Package detection (additional 1 second delay)
5. Job tracking prevents duplicate notifications

### Caching:
- Jupyter availability: 30 seconds
- Kernel list: 10 seconds
- Package checks: 5 seconds

### Job Tracking:
- Installation jobs tracked with unique IDs
- Prevents overlapping installations
- No duplicate notifications during active jobs

## 📝 Configuration Files

### Key Files:
- `lua/pyworks/autocmds.lua` - File detection and workflow triggers
- `lua/pyworks/molten.lua` - Kernel initialization logic
- `lua/pyworks/package-detector.lua` - Import scanning and package detection
- `lua/pyworks/config.lua` - Job tracking and state management

## 🔄 Recent Improvements

1. **Auto Python Host Recovery** - Fixes pynvim issues automatically
2. **Package Name Normalization** - Handles common import mistakes
3. **Job Tracking** - Prevents notification spam
4. **Enhanced Diagnostics** - Better troubleshooting information
5. **Consistent Workflow** - All file types use same notification pattern

## 📊 Testing the Workflow

### Test Files Available:
- `test_execution.py` - Python with cells
- `test_julia.jl` - Julia test file
- `test_r.R` - R test file
- `test_packages.py` - Package compatibility testing

### Expected Behavior:
1. Open any test file
2. See detection notification immediately
3. See kernel check notification after ~1 second
4. See initialization success or selection dialog
5. For Python: see package detection after ~2 seconds

## 🐛 Known Issues

1. **Timing sensitivity**: Notifications may not appear if Neovim loads too slowly
2. **Molten dependency**: Workflow requires Molten to be properly installed
3. **First-time setup**: May need Neovim restart after initial setup

## 💡 Tips

- Use `:PyworksCheckEnvironment` to verify setup
- Use `:PyworksDebug` to check Python host configuration
- Check `:messages` for any error details
- Restart Neovim after installing Molten or fixing Python host