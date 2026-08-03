#!/usr/bin/env python3
"""Replay Molten's kernel-client sequence and report where it stops.

Molten reads no kernel message until jupyter_client's wait_for_ready() returns.
If that never succeeds, every cell sits on "* On Hold" forever with a kernel
that works fine everywhere else. This says which of those two worlds you are in.

Run with the SAME interpreter Neovim uses as its python3 host:
    /path/to/.venv/bin/python molten_probe.py <kernel-name>
"""
import sys, time
from queue import Empty

try:
    import jupyter_client
except ImportError:
    sys.exit("jupyter_client is not installed in this interpreter")

kernel_name = sys.argv[1] if len(sys.argv) > 1 else "python3"
print(f"jupyter_client {jupyter_client.__version__}, kernel {kernel_name!r}")

km = jupyter_client.manager.KernelManager(kernel_name=kernel_name)
km.start_kernel()
kc = km.client()
kc.start_channels()
print("kernel process started:", km.is_alive())

deadline = time.time() + 30
ready = False
while time.time() < deadline:
    try:
        kc.wait_for_ready(timeout=0)
        ready = True
        break
    except RuntimeError:
        time.sleep(0.1)

print("wait_for_ready succeeded:", ready)
if not ready:
    print("\n>>> This is the failure. The kernel runs but never becomes ready to")
    print(">>> jupyter_client, so Molten never processes its messages.")
    km.shutdown_kernel(now=True)
    sys.exit(1)

kc.execute("1+1")
status = "HOLD"
deadline = time.time() + 20
while time.time() < deadline and status != "DONE":
    try:
        msg = kc.get_iopub_msg(timeout=0.2)
    except Empty:
        continue
    if msg["msg_type"] == "execute_input":
        status = "RUNNING"
    elif msg["msg_type"] == "status" and msg["content"].get("execution_state") == "idle":
        status = "DONE"

print("cell reached:", status)
km.shutdown_kernel(now=True)
print("\nAll good — the kernel path works in this interpreter." if status == "DONE"
      else "\n>>> The kernel became ready but the cell never completed.")
