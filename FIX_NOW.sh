#!/bin/bash

# Emergency fix script for Molten hanging issue

echo "Emergency Molten Fix Script"
echo "=========================="
echo ""
echo "This will disable Molten temporarily and fix the installation"
echo ""

# Step 1: Create a temporary init file that disables Molten
TEMP_INIT="$HOME/.config/nvim/init_emergency.lua"
cat > "$TEMP_INIT" << 'EOF'
-- Emergency init to disable Molten
vim.g.molten_error_detected = true
vim.g.loaded_remote_plugins = true  -- Prevent loading remote plugins

-- Load your normal config
local config_path = vim.fn.stdpath("config") .. "/init.lua"
if vim.fn.filereadable(config_path) == 1 then
  dofile(config_path)
end

-- Show message
vim.notify("Molten disabled for emergency fix", vim.log.levels.WARN)
EOF

echo "Step 1: Opening Neovim with Molten disabled..."
nvim -u "$TEMP_INIT" -c "UpdateRemotePlugins" -c "qa!"

echo ""
echo "Step 2: Fixing Python dependencies..."
python3 -m pip install --upgrade pynvim neovim

echo ""
echo "Step 3: Cleaning up..."
rm -f "$TEMP_INIT"

echo ""
echo "✅ Fix complete! You can now start Neovim normally."
echo ""
echo "If issues persist, run: PYWORKS_NO_MOLTEN=1 nvim"