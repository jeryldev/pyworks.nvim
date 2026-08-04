# Changelog

All notable changes to pyworks.nvim will be documented in this file.

## [Unreleased]

## [0.5.1] - 2026-08-04

Fixes issue #10: cells sitting on `* On Hold` for tens of minutes with a
perfectly healthy kernel.

### Fixed

- **Molten was left polling the kernel every 16.7 minutes.** The reload guard
  raised `g:molten_tick_rate` to 999999 while jupytext rewrote the buffer, then
  restored it. Restoring is not enough: Molten reads that variable exactly once,
  when its rplugin host initialises, and bakes it into `timer_start()`. A Molten
  that initialised inside that window kept the huge interval for the rest of the
  session while the variable read a healthy 100 beside it. Readiness is only
  ever noticed inside that timer's callback, so a kernel that started in a
  second went unnoticed for half an hour. The raise is gone entirely — the
  fork's `MoltenTick` reentrancy guard is what it was working around. This is
  the same user-visible symptom as the v0.4.1 and v0.5.0 tick-rate fixes, which
  corrected the unwind without removing the latch underneath
- **Cells were submitted into kernels Molten considered unready.** After 10s
  without a `MoltenKernelReady`, `run_when_ready` ran anyway, assuming the event
  had been missed. Work submitted before Molten is ready is exactly what strands
  a cell on `* On Hold`. It still runs rather than eating the keypress, but now
  says why nothing may come back
- **`:MoltenInit` reporting success meant nothing.** Molten starts kernels on
  its rplugin host and reports failures there, asynchronously, so `vim.cmd`
  returned success even when no kernel existed — pyworks then set
  `b:molten_initialized`, announced "Starting kernel…", and never spoke again. A
  watchdog now reports a kernel that never becomes ready
- **Molten's connection-file directory was never created.** Molten builds
  `<jupyter data dir>/runtime/kernel-<id>.json` by hand and calls
  `write_connection_file()`, which does not create the parent. When it is
  missing the write fails inside the host while `:MoltenInit` still looks fine

### Added

- **`:PyworksReport` reports the interval Molten's tick timer actually fires
  at**, not just that it exists. A timer latched at the old reload rate is
  "running" while polling twice an hour, with `molten tick rate: 100` beside it
  — the combination that hid issue #10 through six rounds of diagnostics
- **`:checkhealth` and `:PyworksReport` name which molten-nvim is installed.**
  lazy.nvim keeps a pre-existing `benlubas/molten-nvim` over the fork pyworks
  declares, leaving users without the `MoltenTick` reentrancy guard
- **`docker/nvim_readiness_probe.py`** — measures Molten's readiness call inside
  Neovim's own Python host, separating "the call is broken" from "Molten is not
  reaching it". Run with `:py3file`
- **`docker/replicate_tick_latch.lua`** — reproduces the tick-rate latch both
  ways in the container, as a permanent regression demonstration

### Internal

- `run_tests.sh -f tests/foo_spec.lua` doubled the path prefix, and
  `test_directory()` on a nonexistent path runs nothing and exits 0 — so the
  suite printed "All tests passed" while running no tests at all

## [0.5.0] - 2026-08-02

Minor rather than patch: pyworks no longer sets itself up outside real projects,
and fifteen unused public functions were removed.

### Added

- **`:PyworksReport`** — one paste-ready bug report: environment, kernelspecs
  with an interpreter-exists check, Molten buffer state, essentials installed vs
  missing, `:checkhealth` output and the recent log. `$HOME` is redacted;
  `:PyworksReport!` keeps full paths. Issue #10 needed five round-trips to
  collect information the plugin already had
- **`:PyworksLog`** and `pyworks.core.log` — levels, module tags, lazy
  formatting and an always-on 500-entry ring buffer, replacing three unrelated
  debug switches. Diagnostics no longer travel on the user's notification
  channel, and every module can log (previously one of twenty could)
- **`utils.is_project()`** — answers the question every "only act inside a
  project" guard was asking

### Fixed

- **Notebook saves were not atomic** — `write_notebook` truncated the real
  `.ipynb` before writing and discarded the `close()` error, so a full disk
  reported "Notebook saved" over a destroyed file. Writes now go to a temp file,
  are validated as a notebook, and are renamed into place with the original mode
  preserved. A failed save leaves the existing notebook untouched
- **Warnings were invisible** — with the default config only
  `error`/`action_required`/`first_time`/`progress` messages reached the user;
  plain INFO *and WARN* were dropped, hiding "Ignoring stale kernel…", "No venv
  for …" and "Notebook opened in JSON view". Warnings and errors are never
  suppressed now; routine INFO still is
- **Installed packages reported as missing** — distribution names use hyphens
  where import names use underscores, so `import jupyter_client` was told the
  package was missing on every scan while `jupyter-client` sat installed. Names
  are normalised per PEP 503 before comparison
- **The environment check blocked Neovim for ~2.4 s per file open** — it spawned
  one `python -c "import X"` per essential, synchronously, even when everything
  was installed. One `uv pip list` now narrows and an import probe confirms:
  **2,453 ms → 74 ms**
- **Notebook conversion ran on every open and save** (720–2,037 ms) — results
  are cached by mtime and size, so repeat opens cost nothing
- **Pyworks set itself up outside projects** — `find_project_root` fell back to
  the starting directory, so it never returned nil and every project guard was
  dead code: a stray `.py` in `/tmp`, in a dependency's source, or in `$HOME`
  got a full environment including a venv beside it. Only strong markers now
  establish a project (`main.py`/`app.py` no longer qualify) and `$HOME` never
  does
- **Nested notebook reloads disabled Molten permanently** — the guard saved the
  already-safe tick rate on re-entry, so unwinding restored 999999 and Molten
  stopped ticking for the session: every cell then sat on `* On Hold` with a
  healthy kernel, indistinguishable from the bug fixed in v0.4.1
- **Opening two notebooks quickly skipped the second conversion** — the reload
  debounce was global; it is now per buffer
- **`:PyworksRunCell` bypassed the kernel-readiness gate** — the guard lived on
  the keymaps, so the commands that exist for `skip_keymaps` users still lost
  cells to the IOPub flush. It now sits on `run_cell` itself
- **A corrupt state file broke `setup()`** — `pairs()` over a decoded `null`
  threw; the file is written from a debounced timer, so a hard exit can leave
  exactly that. `state.remove` also never persisted, so deleted keys returned
- **"Environment ready" appeared once per machine, ever** — the flag was keyed
  by language and persisted; it is now per project, and names it
- **Essentials could be installed into an ambient environment silently** — a
  project without `.venv` adopted whatever `$VIRTUAL_ENV`/`$CONDA_PREFIX` the
  shell had active. That is now announced before installing
- **`protected_call`'s first return means "did not throw"**, not "succeeded" —
  two callers read it as success, so package sync continued after venv creation
  failed and notebook creation continued after setup failed
- Cache stats ignored per-entry TTLs; `cache.configure` dropped typo'd keys
  silently; cell renumbering could act on the wrong buffer; the jupytext
  dependency check looked in `cwd`'s venv rather than the file's project; an
  unknown terminal was handed the kitty image backend

- **"Python environment ready" was announced before the packages existed**: the
  essentials install runs asynchronously, but `ensure_environment` (and
  `:PyworksSetup`) reported success as soon as it was *started*. Running
  `jupyter lab` at that point failed with "jupyter not found" while uv/pip was
  still fetching. Readiness is now reported from an `on_complete` callback, once
  the install has actually finished, and a notification names the packages being
  installed while it runs
- **`:PyworksSetup` could silently do nothing and still report success**:
  `ensure_environment` skips work if it ran within the last 30 seconds, but
  returned `true` regardless, so a repeat run - the natural response to a failed
  setup - claimed success without touching anything. Explicit commands now pass
  `force` and always run; the throttle still applies to automatic checks on file
  open
- **`:PyworksSetup` reported success even when setup failed**:
  `error_handler.protected_call` returns whether the call *threw*, not what it
  returned, so a `false` result still printed "Python environment ready"

### Changed

- **Removed fifteen unused public functions** with no callers, tests or docs:
  `utils.{is_venv_configured,ensure_venv_in_path,detect_package_manager,better_select,command_exists,safe_schedule}`,
  `dependencies.install_dependencies`,
  `error_handler.{validate_executable,handle_job_error,show_error_details}`,
  `notifications.{progress_update,notify_first_time,notify_package_installed}`,
  `python.check_compatibility`, `jupytext.install_jupytext`
- The essentials list has a single source: `init.lua` derives its default from
  `languages/python`'s toolchain rather than restating it
- `vim.validate` added to the public API of `languages/python` and
  `core/packages`

### Internal

- Test suite grew from 300 to 405 tests across 22 spec files; `core/state`,
  `core/notifications`, `core/log`, `core/recursion_guard` and the report
  generator gained their first specs
- Per-module line coverage via a vendored `debug.sethook` collector
  (`./run_tests.sh --coverage`); luacov cannot be used here because luarocks
  targets Lua 5.5 while Neovim runs LuaJIT
- Hermetic project fixture for tests, after a spec created a `.venv` inside the
  checkout on CI
- `run_tests.sh -f` now passes `minimal_init` to the child process, so
  single-file runs match the full suite


## [0.4.1] - 2026-08-01

### Added

- **Stale kernel detection** (#10): a kernelspec registered by
  `ipykernel install --user` bakes an absolute interpreter path into
  `kernel.json`. Move the project or recreate `.venv` and the kernel still
  resolves by name while its python is gone - Molten attaches, no kernel
  process starts, and every cell sits on `* On Hold` with no error.
  Pyworks now:
  - refuses to select a kernel whose interpreter no longer exists, falling
    through to registering a fresh one for the project venv
    (`detector.select_matching_kernel`)
  - reports stale kernels in `:checkhealth pyworks` under a new
    **Jupyter Kernels** section, instead of reporting all-green
  - lists them in `:PyworksDiagnostics` with the removal command
- **`detector.get_kernelspecs()` / `detector.list_stale_kernels()`**: the
  kernelspec query and staleness scan are now public and unit-tested
- **`stylua.toml`**: the formatting contract (tabs, 120 columns) is declared
  instead of relying on stylua's defaults, which a release could change

### Fixed

- **First cell hung on `* On Hold` forever** (#10): `<leader>jl` auto-initialised
  the kernel and then evaluated 100 ms later. Molten does not consume any kernel
  message until `jupyter_client`'s `wait_for_ready()` returns, and that call
  ends by flushing the IOPub channel - so a cell submitted during kernel startup
  has its `execute_input` / `status` messages drained before Molten sees them,
  and the output sits on `* On Hold` forever with a healthy kernel and no error.
  Reproduced against ipykernel 7.3.0 / jupyter_client 8.9.1: the same execution
  reaches `DONE` when sent after readiness and stays at `HOLD` when sent before.
  Kernel readiness is now tracked in `pyworks.core.kernel_ready`, registered at
  plugin load, and every run keymap (`<leader>jl`, `jj`, `jk`, `jR`) waits for
  it. Pressing a run key early is safe: it reports "Waiting for the kernel to be
  ready..." and runs by itself.

  Molten announces readiness as a one-shot event with no way to query it
  afterwards, so readiness is recorded per kernel id rather than only latched
  onto a buffer. Registering the listener from `keymaps.lua` (loaded on
  `FileType python`, which jupytext delays for `.ipynb`) could miss the event
  entirely, leaving every run to sit out the fallback timeout
- **Auto-init announced a kernel that was not ready**: opening a file logged
  "Molten ready with <kernel> kernel - Use `<leader>jl` to run code" the moment
  `MoltenInit` returned, inviting the user to run code during exactly the window
  where executions are silently dropped. It now says the kernel is *starting*,
  and readiness is announced by Molten itself
- **"Invalid buffer id" error from kernel auto-init**: `auto_init_molten`
  captures the buffer, waits 200ms, then writes buffer-local variables. If the
  buffer was gone by then - jupytext replacing an `.ipynb` buffer, or the user
  closing the file - `vim.b[<invalid>]` threw out of a `vim.schedule` callback,
  where nothing could catch it. Deferred writes now go through
  `utils.safe_buf_set_var`, and `pyworks.core.kernel_ready` tolerates being
  asked about a buffer that no longer exists
- **CI linters tracked "latest"**: both stylua and selene were installed from
  the newest upstream release, so an upstream change could turn CI red with no
  change to this repo. Both are now pinned (stylua v2.5.2, selene 0.31.0).
  The formatting job had in fact been failing since before v0.2.0, which also
  meant the selene step never ran
- **`health.lua` passed `gsub`'s substitution count** as the advice argument to
  `health.ok` / `health.error`

## [0.4.0] - 2026-07-31

### Added

- **`jupyterlab` in the default essentials**: creating a notebook (or any
  environment setup) now installs JupyterLab into the project venv, so the
  same project opens in the browser with `.venv/bin/jupyter lab`. The
  kernel is the venv's own `ipykernel`, shared with Molten inside Neovim,
  and the `jupyterlab_jupytext` server extension loads automatically so
  `# %%` scripts open as notebooks in Lab too. Costs ~94 MB on top of the
  previous essentials (188 MB -> 282 MB measured). Opt out by passing your
  own `python.essentials` list
- **`python.get_essentials()`**: returns the effective essentials list, so
  the set installed on notebook creation is inspectable

### Fixed

- **Run-all (`<leader>jR`) executed the wrong cell and never skipped
  markdown** (#10): run-all parks the cursor on the cell marker line, but
  `is_markdown_cell` and `evaluate_percent_cell` searched backwards with
  `"bnW"`. Without the `c` flag a match at the cursor is rejected, so both
  read the *previous* marker - markdown cells were executed and then
  waited on for the full 30s timeout, and the evaluated range spanned the
  previous cell plus the current one. Both now delegate to `cell_engine`,
  which searches with `"bcnW"`
- **Run-all skipped the first cell when line 1 is a marker**: navigation
  searched forward N times from line 1, which excludes a match on line 1
  and ran cell N+1 for every N. Cells are now indexed directly by marker
  position

## [0.3.0] - 2026-05-22

### Added

- **`molten.virt_text_max_lines` setup option**: The virtual-text output cap
  (introduced in v0.2.0) is now user-configurable. Default remains `500`.
  Example: `require("pyworks").setup({ molten = { virt_text_max_lines = 1000 } })`
- **`vim.validate` parameter checks** on public `cell_engine` API
  (`run_cell`, `configure`, `count_cells`, `get_cell_positions`) per
  CLAUDE.md mandate. Misuse from external callers now fails fast with a
  clear error
- **`PyworksRunCell` / `PyworksRunCellAdvance` in integration test
  expected-commands list** to prevent future regressions

### Fixed

- **`molten_virt_text_max_lines` set in two places**: De-duplicated the
  cap so both call sites now read from a single config source. Previous
  versions silently overrode `configure_dependencies()`'s value with a
  hardcoded `500` later in `setup()`
- **Empty notify prefix in `:PyworksNewPythonNotebook`**: Removed the
  `"" .. json_err` / `"" .. write_err` concat which produced
  notifications starting with an empty string
- **Filename validation gaps in `:PyworksNewPythonNotebook`**: Directory
  traversal (`..`) check and Windows-reserved backslash (`\`) check are
  now part of `validate_filename` instead of an ad-hoc inline block, so
  every notebook-creation entry point gets the same protection
- **`processing_buffers` stuck on error in jupytext reader**: Wrapped
  `read_notebook` body in `pcall` so the per-buffer "processing" flag is
  always cleared, even if `nvim_buf_set_lines` or jupytext throws. Bug
  could leave buffers unable to reload after a single failure
- **Dead `search_flags` variable in `cell_engine.prev_cell`**: Removed
  redundant branch that assigned the same value in both arms then never
  used the variable

### Changed

- **Hot-path string concat in `concat_virt_text`**: Switched from
  `text = text .. ...` accumulator to `table.concat` for the per-extmark
  virtual-text join. Called every 150 ms during cell-completion polling
  on large output cells; O(n²) → O(n)
- **`<leader>jv` and `<leader>jg` use API calls instead of `normal!`**:
  Visual-select-current-cell and go-to-cell-N now work from terminal
  mode and avoid the `normal! <count>G` quirks. `<leader>jv` also
  delegates boundary detection to `cell_engine.find_cell_boundaries`
  (uses `bcnW` — accepts a marker at cursor position — matching the
  rest of the cell engine)
- **Raw `vim.notify(..., ERROR)` in `commands/create.lua` replaced with
  `notifications.notify_error`**: Single consistent error pathway,
  enables future error-handling work (rate limiting, history tracking)
- **`create_floating_window` width is now adaptive**: Clamped to
  `min(opts.width, columns - 4)` so `:PyworksHelp` and similar popups
  remain visible on narrow terminals (≤100 cols)

### Removed

- **Dead `M.health` in `init.lua`**: `:checkhealth pyworks` was always
  routed through `lua/pyworks/health.lua`. The duplicate definition in
  `init.lua` was unused

## [0.2.0] - 2026-05-21

### Fixed

- **Neovim freeze on tqdm-heavy cells (issue from bart.ipynb)**: Capped
  `molten_virt_text_max_lines` at `500` (was `999999`). Output with thousands
  of carriage-return-overwriting lines (HuggingFace `datasets` shard
  extraction, deep training logs) no longer stalls the UI thread while
  Molten renders every line as an extmark. Use `:MoltenEnterOutput` or
  `disable_progress_bar()` for very long output.

### Added

- **`:PyworksRunCell`** and **`:PyworksRunCellAdvance`** user commands for
  `skip_keymaps` users — run the current cell in place, or run and advance
  to the next cell (closes feedback on issue #4 — no wrapper existed for
  running the current cell from Lua/commands)
- **`require("pyworks.core.cell_engine").run_cell(opts)`** public Lua API.
  Pass `{ advance = true }` to mirror Jupyter Shift+Enter behavior. Returns
  `false` when no kernel is initialized or the cell is empty
- Test coverage for `run_cell` (7 scenarios) and the two new user commands

### Changed

- **`<leader>jj` / `<leader>jk` delegate to `cell_engine.run_cell()`**:
  Both keymaps now call the public API instead of duplicating execution
  logic in `keymaps.lua`. Single source of truth — keymap and command
  behavior cannot drift
- **Switched to maintained forks**: Dependencies (`jeryldev/molten-nvim`,
  `jeryldev/image.nvim`) are now declared in `lazy.lua` and installed automatically.
  Users only need `"jeryldev/pyworks.nvim"` in their config — no separate
  dependency lines required. Both forks track upstream with upstream remotes.
- **Removed runtime molten patching**: `molten_patches.lua` removed. Bug fixes for
  dict iteration safety and MoltenTick reentrancy are baked into the fork
- **Paused MoltenTick during reloads**: Safe tick rate set to effectively disabled
  during notebook reload operations to prevent reentrancy

### Fixed

- **Jupytext cache TTL**: Fixed `cache.set()` calls passing unsupported third argument;
  TTL is now correctly derived from the cache key prefix (`jupytext_check` = 1 hour)
- **Shell injection in kernel creation**: `project_name` in `--display-name` is now
  shell-escaped via `vim.fn.shellescape()`, preventing breakage with special characters
- **Wrong venv in `analyze_buffer`**: `get_installed_packages()` now receives `filepath`
  to check the correct project venv instead of cwd
- **Wrong venv in `install_essentials`**: `get_pip_path()` now receives `filepath` to
  resolve pip from the correct project venv
- **Removed ghost command from help**: `:PyworksDebugExtmarks` listed in `:PyworksHelp`
  but never registered; removed from help text and vimdoc

### Added

- **Run cell without moving cursor (`<leader>jk`)**: Execute current cell and stay in place,
  complementing `<leader>jj` which runs and moves to the next cell
- **Cell operation commands for `skip_keymaps` users**: `:PyworksNextCell`, `:PyworksPrevCell`,
  `:PyworksInsertCellAbove`, `:PyworksInsertCellBelow`, `:PyworksToggleCellType`,
  `:PyworksMergeCellBelow`, `:PyworksSplitCell`
- **Configurable cell delimiter (`cell_marker`)**: Set `cell_marker = "# COMMAND ----------"` for
  Databricks or other non-standard cell delimiters (default: `"# %%"`)
- **Improved venv detection via environment variables**: Now respects `$VIRTUAL_ENV` and
  `$CONDA_PREFIX`. Priority: local `.venv` > `$VIRTUAL_ENV` > `$CONDA_PREFIX` > fallback

### Fixed

- **Terminal mode error in `<leader>jR`**: Fixed "Can't re-enter normal mode from terminal mode"
  error when running all cells. Now uses `vim.api.nvim_win_set_cursor()` API calls instead of
  `normal!` commands, which work from any mode including terminal mode.
- **Faster Molten tick rate during reload**: Reduced safe tick rate from 1000ms to 500ms for
  better responsiveness during notebook reload operations.
- **Timer double-close error**: Use libuv's `is_closing()` API to prevent "handle is already closing"
  errors when Molten crashes during cell execution polling

### Changed

- **`<leader>jR` cursor positioning**: Now moves cursor to next cell immediately after starting
  execution (matching `<leader>jj` behavior), so output appears above the cursor as cells run
- **Documentation accuracy**: Updated `<leader>jl` description from "Auto-initialize kernel" to
  "Run current line (auto-initializes kernel on first use)" across README, help file, and keymaps
- **Removed floating window keymaps (`<leader>jo`, `<leader>jh`, `K`)** - These controlled Molten's
  floating output window which is not Jupyter-like. Output now follows Jupyter behavior:
  - Output appears inline below cells (Molten's default)
  - Use `<leader>jd` to clear output
  - Use `<leader>jj` to re-run cell and see output again
  - Removed `K` override - use your existing LSP hover configuration

- **Breaking: Removed jupytext.nvim dependency** - pyworks.nvim now handles .ipynb files directly
  - Uses jupytext CLI directly for notebook conversion (automatically installed as Python package)
  - No longer requires jupytext.nvim plugin in dependencies
  - Prevents autocmd conflicts and E325 swap file errors
  - Disables swap files for .ipynb buffers to avoid interactive prompt issues
  - Provides graceful fallback to JSON view when jupytext CLI is not installed
  - Auto-detects jupytext.nvim and warns about potential conflicts
  - Set `skip_jupytext = true` if you prefer to use jupytext.nvim instead
  - Update your lazy.nvim config to remove jupytext.nvim from dependencies

### Fixed

- **Cell execution now shows diagrams and tables**: Changed from `nvim_feedkeys` visual mode
  simulation to `MoltenEvaluateRange` function call, making `<leader>jj` and `<leader>jR`
  display output consistently with `<leader>jv` + `<leader>jr`

- **Molten extmark bug workaround**: Event suppression during run-all cell execution
  - Suppresses CursorMoved events during navigation to prevent Molten extmark issues
  - Uses API calls instead of `normal!` commands to work from any mode
  - Calls MoltenDeinit before notebook buffer reloads and on session restore
  - Workaround for upstream Molten bug in position.py

- **Breaking: Reorganized Cell Execution and Folding Keymaps**:
  - `<leader>jj` - Run cell and move to next (was `<leader>jc`)
  - `<leader>jc` - Collapse current cell (NEW)
  - `<leader>jC` - Collapse all cells (was `<leader>jzc`)
  - `<leader>je` - Expand current cell (was "re-evaluate current cell")
  - `<leader>jE` - Expand all cells (was `<leader>jze`)
  - Removed `<leader>je` for re-evaluate (redundant with `<leader>jj`)
- **Improved Cell Folding**: Collapse/expand commands now auto-enable folding if not already active

### Added

- **Configurable Custom Package Prefixes**: Package detection now supports user-defined prefixes
  - Configure via `packages.custom_package_prefixes` in setup()
  - Default prefixes: `^my_`, `^custom_`, `^local_`, `^internal_`, `^private_`, `^app_`, `^lib_`, `^src$`, `^utils$`, `^helpers$`
  - Prevents suggesting installation of company-internal or local packages
- **Test Coverage for UI Module**: Added comprehensive tests for ui.lua
  - Tests for cell highlighting, execution tracking, numbering, and folding
  - 11 new test cases covering all major UI functions
- **Run All Cells (`<leader>jR`)**: Execute all cells sequentially from top to bottom
  - Waits for each cell to complete before running the next (like PyCharm/Jupyter)
  - Detects completion by monitoring Molten's extmarks for output (`Out[N]:`)
  - 30-second timeout per cell prevents hanging on long-running cells
  - Shows progress notification and positions cursor at last cell when complete
- **Cell Folding & UI Enhancements**: New visual features for better cell organization
  - Cell folding: Collapse/expand cells with `<leader>jf`, `<leader>jc/jC`, `<leader>je/jE`
  - Cell numbering: Automatic inline cell numbering with type indicators (code/markdown)
  - Execution status: Cell numbers change from red (unrun) to green (executed) when cells are run
  - Tracks execution state per buffer - visual feedback for which cells have been executed
  - Custom fold text showing cell type, line count, and content preview
  - Configurable via `setup({ show_cell_numbers = true, enable_cell_folding = false })`
- **Jupyter-like Keybindings**: Comprehensive cell manipulation and execution
  - Cell execution: `<leader>jj` (run and move next), `<leader>jR` (run all)
  - Cell creation: `<leader>ja/jb` (insert code cells above/below), `<leader>jma/jmb` (insert markdown cells)
  - Cell operations: `<leader>jt` (toggle type), `<leader>jJ` (merge below), `<leader>js` (split at cursor)
  - Output management: `<leader>jd` (clear output)
  - Navigation: `<leader>jg` (go to cell N), `<leader>j]/j[` (next/prev cell)
  - Kernel management: `<leader>mi` (initialize), `<leader>mI` (show info)

### Fixed

- **Security: Pip Action Whitelist**: Added validation for pip command actions
  - Only allows safe actions: install, uninstall, list, show, freeze
  - Prevents potential command injection via malicious package names
- **Security: File Size Check**: Added size limit before reading files for import scanning
  - Prevents memory issues with very large files
  - Default limit: 1MB (configurable)
- **Cell Toggle (`<leader>jt`)**: Fixed toggle not working from markdown back to code
  - Simplified pattern matching to check for `[markdown]` substring instead of complex regex
  - Now correctly toggles between `# %%` and `# %% [markdown]` in both directions
- **Cell Navigation (`<leader>jg`)**: Reimplemented to work without executing cells
  - Previously used `MoltenGoto` which required cells to be executed first
  - Now searches for `# %%` markers directly, enabling navigation before execution
  - Shows helpful error if requested cell number doesn't exist
  - Restores cursor position on error for better UX
- **Molten Cell Execution for Percent-Format Scripts**: Fixed "not in a cell" errors
  - `<leader>jc` and `<leader>je` now work correctly with `# %%` delimited cells
  - Added `evaluate_percent_cell()` helper that finds code between `# %%` markers
  - Properly excludes `# %%` markers from execution (only executes cell content)
  - Uses visual selection to create Molten cells on-the-fly
  - Keybindings now work whether or not a Molten cell exists
- **Cursor Movement After Cell Execution**: Fixed `<leader>jc` not moving to next cell
  - Removed cursor restoration from `evaluate_percent_cell()` to prevent overwriting navigation
  - Added proper cursor positioning control in `<leader>jc` (move to next) and `<leader>je` (stay in place)
  - Cell execution now properly mimics Jupyter's Shift+Enter behavior

### Changed

- **Code Quality: Extracted filter_pip_stderr Helper**: Reduced complexity in python.lua
  - Filters out pip noise (WARNING, Resolved, Installed, Collecting messages)
  - Cleaner error output for package installation failures
- **Breaking**: `<leader>jj` is now "run cell and move to next" (was `<leader>jc`)
  - `<leader>jc` is now "collapse current cell"
  - Use `<leader>jv` for visual select cell (better vim semantics)
- **Documentation**: Simplified README and help docs by removing verbose sections
  - Removed "Why This Simple Configuration Works" section
  - Removed "What's New in v3.0" marketing language
  - Removed "The Six Core Scenarios" section
  - Consolidated Jupyter Notebook Support into Quick Start
- **Focus**: Simplified to Python-only
  - Removed Julia and R language support
  - Renamed package commands for clarity (Sync/Add/Remove/List)
  - Added `:PyworksHelp` command for quick reference

### Documentation

- **Fixed Neovim Version Requirement**: Updated from ≥0.9.0 to ≥0.10.0 (code uses `vim.system()` and `vim.uv` APIs)
- **Expanded Project Detection Markers**: Documented all 16+ supported markers including uv.lock, poetry.lock, manage.py, etc.
- **Added Missing Keymaps to Help Doc**: Added `<leader>jR`, `<leader>jf`, `<leader>jc/jC`, `<leader>je/jE`, `<leader>jn`
- **Synced Configuration Section**: README now matches actual init.lua defaults
- Added active development warning to README
- Updated all keybinding tables with comprehensive new set (24 total keybindings)
- Reorganized keybindings into logical categories (Execution, Navigation, Output, Creation, Operations, Kernel)
- Updated typical workflow examples with new keybindings

## [3.0.2] - 2025-01-08

### Added

- **Notebook Creation Commands**: Commands for creating notebooks with templates
  - `:PyworksNewPython [name]` - Create Python file with cell markers and common imports
  - `:PyworksNewPythonNotebook [name]` - Create proper .ipynb with Python kernel
- **LazyVim Configuration Example**: Added `examples/lazyvim-setup.lua` with exact working configuration
- **Molten Virtual Text Output**: Enabled `molten_virt_text_output=true` for persistent cell output with images

### Fixed

- **Configuration Order**: Fixed jupytext.nvim to use `config = true` for proper setup
- **Molten Cell Persistence**: Cells now properly show output when cursor returns to them
- **Image Display**: Images now display correctly in Molten output windows alongside text

### Documentation

- Added complete workflow guide in README
- Updated help file with practical examples and quick start guide
- Cleaned up outdated commands and non-existent features
- Added comprehensive command and keymap reference tables

## [3.0.1] - 2025-01-08

### Added

- **Python Package Management Commands**:
  - `:PyworksAdd <packages>` - Add packages to project venv
  - `:PyworksRemove <packages>` - Remove packages from project venv
  - `:PyworksList` - List all installed packages in a buffer
  - `:PyworksSync` - Install missing packages detected from imports
- **Enhanced Error Reporting**: Detailed error buffers for package installation failures with full output and troubleshooting steps
- **Smart Package Filtering**:
  - Automatically ignores standard library modules (base64, os, sys, etc.)
  - Filters out custom/local packages (company-specific prefixes like seell_, my_, internal_)
  - Only suggests real PyPI packages for installation

### Fixed

- **Per-Project Python Configuration**: Each project now correctly uses its own Python environment
- **UV/pip Detection**: Improved detection of UV vs regular pip virtual environments
  - Checks for `uv = ` marker in pyvenv.cfg
  - Verifies uv.lock presence
  - Falls back to pip for non-UV venvs
- **File Path Handling**: Consistent use of absolute paths throughout the codebase
- **Package Installation**: Better handling of missing packages with improved logging

### Changed

- **Package Detection Logic**: More robust filtering to avoid installing non-existent packages
- **Virtual Environment Detection**: Now uses file's directory instead of current working directory
- **Error Messages**: More informative error messages with actionable troubleshooting steps

## [3.0.0] - 2024-08-08

### Major Rewrite - Complete Architecture Overhaul

#### Added

- **Zero-Configuration Workflow**: Automatic environment setup for Python without any manual steps
- **Auto-Initialization**: Molten kernels initialize automatically when compatible kernel exists
- **Dynamic Kernel Detection**: Queries available kernels instead of hardcoded names
- **Project-Based Activation**: Only runs in directories with project markers (.venv, pyproject.toml, etc.)
- **Hover-Based Output**: Molten outputs display on demand, not inline (cleaner workspace)
- **Smart Package Detection**: Improved detection with proper async handling
- **Cell Navigation**: [j and ]j keymaps for navigating between cells (avoiding LazyVim conflicts)
- **Visual Selection Fix**: Proper handling of visual mode for cell execution

#### Changed

- **Complete Restructure**: Modular architecture with separate core, languages, and notebook modules
- **Improved Caching**: Aggressive caching with TTL for better performance
- **Better Notifications**: Only shows notifications when action needed, silent when ready
- **Jupytext Integration**: Automatic jupytext installation and PATH configuration
- **Image Display**: Fixed to show only in Molten popup, not external applications

#### Fixed

- **Kernel Name Mismatch**: Kernels now detected dynamically
- **Visual Selection Error**: "No visual selection found" error with proper `:<C-u>` handling
- **Auto-Initialization**: Now works for all 6 scenarios including notebooks
- **Package Installation**: Notifications only show after actual completion
- **Global Activation**: Pyworks only activates in project directories
- **Image Popup**: Disabled auto_image_popup to prevent external viewer launches

#### Removed

- **Legacy Code**: Removed all v2 code and migrated to clean v3 architecture
- **Test Files**: Moved all tests and documentation to notes/ folder
- **Redundant Features**: Removed duplicate functionality and streamlined workflows

## [2.0.0] - 2024-01-08

### Added

- **Python Kernel Support**: Automatic detection and initialization for Python
- **Smart Package Detection**: Auto-detects missing Python packages with compatibility checks
- **Package Compatibility Handling**: Detects and warns about Python 3.12+ incompatibilities
- **Alternative Package Suggestions**: Recommends compatible alternatives (e.g., PyTorch for TensorFlow)
- **Enhanced Output Windows**: Increased to 40x150 for better data visualization
- **Consistent Workflow**: All file types trigger same detection and initialization flow

### Changed

- **Unified Experience**: Same workflow for .py and .ipynb files
- **Better Package Detection**: Handles complex import patterns and package name mappings
- **Improved Kernel Matching**: Smart detection based on file type and notebook metadata
- **Optimized Autocmds**: Immediate notifications with deferred initialization

### Fixed

- Unicode separator corruption in notifications
- Package installation command format issues
- Silent mode inconsistencies between file types
- Notebook metadata detection for non-Python languages
- Kernel initialization race conditions
- Package name mapping (scikit-learn, PIL → Pillow)

## [1.5.0] - 2024-01-07

### Performance Improvements

### 1. Implemented Caching Layer ✅

- Added `utils.get_cached()` function for expensive operations
- Cache Jupyter availability checks (30 second TTL)
- Cache kernel list fetching (10 second TTL)
- Reduces repeated file system calls

### 2. Extracted Common venv Logic ✅

- New utility functions in `utils.lua`:
  - `has_venv()` - Check if virtual environment exists
  - `get_python_path()` - Get Python executable from venv
  - `is_venv_configured()` - Check if venv is properly set up
  - `ensure_venv_in_path()` - Add venv to PATH
- Eliminated code duplication across modules

### 3. Converted Critical Blocking Calls to Async ✅

- `complete_setup()` now uses async for:
  - Remote plugin updates
  - Jupyter kernel creation
  - Package installation checks
- UI no longer freezes during setup operations

### 4. Documentation Updates ✅

- Removed outdated `docs/` folder
- Updated README configuration section
- Removed misleading Molten configuration options



