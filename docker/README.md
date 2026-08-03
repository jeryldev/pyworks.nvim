# Reproduction container

Built for issue #10 ("cells stuck on `* On Hold`"), and kept as the live-Molten
harness the test strategy calls Layer 4 — the layer that unit tests cannot
reach, because the bug lives in the interaction between Molten, jupyter_client
and a real kernel.

It reproduces the reporter's environment shape: Linux, Neovim 0.12.x, a
uv-managed Python 3.13, ipykernel 7 / jupyter_client 8, molten-nvim, image.nvim,
and a notebook whose path is non-ASCII.

```bash
docker build -t pyworks-issue10 docker/
docker run --rm -v "$PWD:/work/pyworks:ro" pyworks-issue10
```

The scenario opens the notebook, runs `MoltenInit`, and reports whether
`MoltenKernelReady` fires, how long it took, whether the readiness latch caught
it, and whether a cell actually executes. It ends by printing the pyworks log.

Expected output on a healthy setup:

```
MoltenInit ok:                     true
ready event seen:                  true
time to ready (ms):                848
b:pyworks_kernel_ready:            true
kernel executed the code:          true
```

## molten_probe.py

Standalone: replays Molten's client sequence against a kernel and says whether
`wait_for_ready()` ever succeeds. Run it with the same interpreter Neovim uses
as `python3_host_prog`:

```bash
/path/to/.venv/bin/python docker/molten_probe.py <kernel-name>
```

Molten reads no kernel message until `wait_for_ready()` returns, so a kernel
that works in `jupyter console` but never becomes ready here explains the hang
without involving pyworks at all.

## Two things the harness itself uncovered

- `MoltenInit` fails with ENOENT when `<jupyter data dir>/runtime/` does not
  exist — molten writes its connection file there and does not create the
  directory.
- Molten refuses to start when `molten_image_provider` names a plugin that is
  not installed; pyworks sets it to `image.nvim`.
