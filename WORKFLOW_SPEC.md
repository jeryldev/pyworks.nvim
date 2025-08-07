# Pyworks.nvim Workflow Specification

## Universal Workflow for All File Types

This workflow applies to ALL supported file types: `.ipynb`, `.py`, `.jl`, `.R`

### Step-by-Step Flow

1. **Open the file** (`.ipynb`, `.py`, `.jl`, `.R`)

2. **Detect the file type**
   - For `.ipynb`: Use special function to detect language from notebook metadata
   - For `.py`: Python
   - For `.jl`: Julia  
   - For `.R`: R

3. **Detect if there is an available kernel for the file type detected**
   - Check installed Jupyter kernels
   - Match kernel to detected language

4. **If kernel is available, auto-initialize it**
   - Silently initialize the matching kernel
   - Show success notification

5. **If no matching kernel, show selection dialog**
   - Present list of available kernels
   - Let user choose appropriate kernel

6. **Once kernel is initialized, detect imports in the file**
   - For ALL file types (`.ipynb`, `.py`, `.jl`, `.R`)
   - Scan for language-specific import statements:
     - Python: `import`, `from ... import`
     - Julia: `using`, `import`
     - R: `library()`, `require()`
   - Show notification: "Missing packages: [list]. Press <leader>pi to install"

7. **Show notification after installation attempt**
   - Success: "Successfully installed packages: [list]"
   - Partial: "Installed [list], Failed: [list with reasons]"
   - Skip problematic packages and continue

## Implementation Requirements

- This workflow MUST trigger automatically on file open
- No user configuration should be required
- All steps should have visual feedback (notifications)
- Failures should be graceful with helpful messages

## Key Files to Modify

1. `plugin/pyworks.lua` - Enable auto-setup with defaults
2. `lua/pyworks/autocmds.lua` - Implement the exact workflow
3. `lua/pyworks/molten.lua` - Kernel detection and initialization
4. `lua/pyworks/package-detector.lua` - Extend to support all languages