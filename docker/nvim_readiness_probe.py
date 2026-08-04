"""Time Molten's readiness check from inside Neovim's own Python host.

Run it with the provider, not a shell:

    :py3file /path/to/nvim_readiness_probe.py

(:py3file, not :python3file - the long form is not a command in Neovim 0.12.)

molten_probe.py answers "can this interpreter ever get a kernel ready", and on
the issue #10 machine it says yes. Molten asks the same question and waits 33
minutes for an answer, so the difference is not the interpreter or the kernel -
it is the environment the call runs in. Neovim's python3 provider is the closest
reachable stand-in for the rplugin host: same interpreter, same process model,
same RPC world, without Molten in the way.

Molten's tick does exactly one wait_for_ready(timeout=0) per tick and treats
RuntimeError as "not ready yet", so that is what this repeats and times.

    fast here  -> the call is fine in Neovim; Molten is not reaching it
    slow here  -> the call itself stalls under Neovim, which is the bug
"""

import time

BUDGET_SECONDS = 60

# Inside the provider `vim` is importable, so the probe can use the kernel
# pyworks picked for this buffer instead of asking anyone to edit the file
try:
    import vim

    KERNEL = vim.eval("get(b:, 'pyworks_kernel_name', 'python3')")
except Exception:  # noqa: BLE001 - running outside Neovim is a valid fallback
    KERNEL = "python3"

try:
    import jupyter_client
except ImportError:
    raise SystemExit("jupyter_client is not installed in Neovim's python3 host")

print(f"jupyter_client {jupyter_client.__version__}, kernel {KERNEL!r}")

km = jupyter_client.manager.KernelManager(kernel_name=KERNEL)
km.start_kernel()
kc = km.client()
kc.start_channels()

# Molten rewrites the connection file to a path it builds by hand; mirrored here
# so the probe exercises the same client state Molten's does
kc.connection_file = f"{kc.data_dir}/runtime/kernel-probe.json"
try:
    kc.write_connection_file()
except Exception as exc:  # noqa: BLE001 - the failure itself is the finding
    print(f"write_connection_file failed: {exc!r}")

attempts = 0
ready = False
start = time.time()
while time.time() - start < BUDGET_SECONDS:
    attempts += 1
    try:
        kc.wait_for_ready(timeout=0)
        ready = True
        break
    except RuntimeError:
        time.sleep(0.1)

elapsed = time.time() - start
print(f"ready={ready}  attempts={attempts}  elapsed={elapsed:.2f}s")

if ready and elapsed < 5:
    print(">>> The readiness call is fine inside Neovim.")
    print(">>> Molten is not reaching it, or not acting on the result.")
else:
    print(">>> The readiness call itself stalls under Neovim.")
    print(">>> This is the bug, and it is below Molten.")

kc.stop_channels()
km.shutdown_kernel(now=True)
