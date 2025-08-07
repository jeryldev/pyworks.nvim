# Fix for pgdaiml Kernel Issue

The `pgdaiml` kernel is causing the Python host to crash because its virtual environment doesn't have `pynvim` installed.

## Option 1: Install pynvim in pgdaiml environment (Recommended)
```bash
cd ~/code/pgdaiml
.venv/bin/pip install pynvim jupyter_client ipykernel
```

## Option 2: Remove the pgdaiml kernel
```bash
jupyter kernelspec remove pgdaiml
```

## Option 3: Use a different kernel
When Molten shows the kernel selection dialog, choose `python3` instead of `pgdaiml`.

## Why this happens:
1. The `pgdaiml` kernel uses Python from `/Users/jeryldev/code/pgdaiml/.venv/`
2. That environment is missing `pynvim` which Neovim needs
3. When Molten tries to use this kernel, the Python host crashes

## Prevention:
The updated pyworks now:
- Checks if a project kernel actually matches the current project
- Falls back to `python3` kernel if the project kernel fails
- Provides better error messages when kernels fail