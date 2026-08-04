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

# Which scenario to run; defaults to the readiness regression net. The scenario
# exits non-zero when a check fails, and set -e propagates that as the
# container's exit code, which is what makes this usable from CI.
SCENARIO="${1:-/work/run_scenario.lua}"

# pyworks itself is mounted, not baked, so the container always tests the
# working tree. Without the mount every scenario dies on require("pyworks.*")
# and, because a --headless nvim that errors sits waiting for input rather than
# exiting, the run hangs until CI kills it. Fail loudly in one second instead.
if [ ! -f /work/pyworks/lua/pyworks/init.lua ]; then
    echo "ERROR: pyworks is not mounted at /work/pyworks"
    echo "       run with: -v \"\$PWD:/work/pyworks:ro\""
    exit 1
fi

echo "--- running scenario: $SCENARIO ---"
cd /work/project
# The trailing -c cq only runs if the scenario failed to reach its own exit,
# which means it threw: exit non-zero rather than hanging or passing silently.
nvim --headless -u /work/init.lua -c "luafile $SCENARIO" -c "cq" 2>&1
