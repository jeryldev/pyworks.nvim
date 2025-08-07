# Emergency Molten Disable

If Molten is causing Neovim to hang, add this to your config BEFORE pyworks:

```lua
-- Add this BEFORE loading pyworks
vim.g.molten_error_detected = true
```

Or in your terminal before starting Neovim:
```bash
export PYWORKS_NO_MOLTEN=1
nvim
```

## To fix Molten permanently:

1. Start Neovim with Molten disabled (using above method)
2. Run `:PyworksFixMolten`
3. Restart Neovim
4. Remove the disable flag from your config

## Manual fix if automated fix doesn't work:

```bash
# In terminal:
python3 -m pip install --upgrade pynvim
nvim -c "UpdateRemotePlugins" -c "qa!"
```

Then restart Neovim normally.