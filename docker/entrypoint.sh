#!/bin/sh
set -e
mkdir -p /work/out
echo "nvim:   $(nvim --version | head -1)"
echo "python: $(/work/project/.venv/bin/python --version)"
echo "ipykernel/jupyter_client:"
/work/project/.venv/bin/python -c "import ipykernel, jupyter_client; print('  ipykernel', ipykernel.__version__, '/ jupyter_client', jupyter_client.__version__)"
echo "kernels:"; /work/project/.venv/bin/python -m jupyter kernelspec list 2>/dev/null | sed 's/^/  /'

echo "--- generating molten rplugin manifest ---"
nvim --headless -u /work/init.lua -c "UpdateRemotePlugins" -c "qa" 2>&1 | tail -2

echo "--- running scenario ---"
cd /work/project
nvim --headless -u /work/init.lua -c "luafile /work/run_scenario.lua" 2>&1
