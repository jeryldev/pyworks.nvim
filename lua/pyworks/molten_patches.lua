local M = {}

function M.get_molten_path()
	local lazy_ok, lazy = pcall(require, "lazy.core.config")
	if lazy_ok and lazy.plugins and lazy.plugins["molten-nvim"] then
		local plugin = lazy.plugins["molten-nvim"]
		if plugin.dir then
			return plugin.dir
		end
	end
	return vim.fn.stdpath("data") .. "/lazy/molten-nvim"
end

function M.read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*all")
	f:close()
	return content
end

function M.write_file(path, content)
	local f = io.open(path, "w")
	if not f then
		return false
	end
	f:write(content)
	f:close()
	return true
end

function M.patch_moltenbuffer(molten_dir)
	local path = molten_dir .. "/rplugin/python3/molten/moltenbuffer.py"
	local content = M.read_file(path)
	if not content then
		return false, "moltenbuffer.py not found"
	end

	if not content:find("for span, output in self.outputs.items():", 1, true) then
		return false, "already_patched"
	end

	local patched = content:gsub(
		"for span, output in self%.outputs%.items%(%):",
		"for span, output in list(self.outputs.items()):"
	)
	if patched == content then
		return false, "gsub did not match"
	end

	if not M.write_file(path, patched) then
		return false, "failed to write " .. path
	end

	return true, nil
end

function M.patch_molten_tick(molten_dir)
	local path = molten_dir .. "/rplugin/python3/molten/__init__.py"
	local content = M.read_file(path)
	if not content then
		return false, "molten __init__.py not found"
	end

	if content:find("_ticking", 1, true) then
		return false, "already_patched"
	end

	local old_tick = '    @pynvim.function("MoltenTick", sync=True)  # type: ignore\n'
		.. "    @nvimui  # type: ignore\n"
		.. "    def function_molten_tick(self, _: Any) -> None:\n"
		.. "        self._initialize_if_necessary()\n"
		.. "\n"
		.. "        molten_kernels = self._get_current_buf_kernels(False)\n"
		.. "        if molten_kernels is None:\n"
		.. "            return\n"
		.. "\n"
		.. "        for m in molten_kernels:\n"
		.. "            m.tick()"

	local new_tick = "    _ticking = False\n"
		.. "\n"
		.. '    @pynvim.function("MoltenTick", sync=True)  # type: ignore\n'
		.. "    @nvimui  # type: ignore\n"
		.. "    def function_molten_tick(self, _: Any) -> None:\n"
		.. "        if self._ticking:\n"
		.. "            return\n"
		.. "        self._ticking = True\n"
		.. "        try:\n"
		.. "            self._initialize_if_necessary()\n"
		.. "\n"
		.. "            molten_kernels = self._get_current_buf_kernels(False)\n"
		.. "            if molten_kernels is None:\n"
		.. "                return\n"
		.. "\n"
		.. "            for m in molten_kernels:\n"
		.. "                m.tick()\n"
		.. "        finally:\n"
		.. "            self._ticking = False"

	local patched, count = content:gsub(vim.pesc(old_tick), new_tick)
	if count == 0 then
		return false, "tick function signature did not match upstream (may have changed)"
	end

	if not M.write_file(path, patched) then
		return false, "failed to write " .. path
	end

	return true, nil
end

function M.apply_patches()
	local molten_dir = M.get_molten_path()
	local results = {}

	local ok1, err1 = M.patch_moltenbuffer(molten_dir)
	table.insert(results, { name = "dict_iteration", applied = ok1, reason = err1 })

	local ok2, err2 = M.patch_molten_tick(molten_dir)
	table.insert(results, { name = "tick_reentrancy", applied = ok2, reason = err2 })

	local patched_any = ok1 or ok2
	local failed_any = false

	for _, r in ipairs(results) do
		if not r.applied and r.reason and r.reason ~= "already_patched" then
			failed_any = true
		end
	end

	if patched_any then
		vim.schedule(function()
			vim.notify(
				"[pyworks] Molten patches applied. Restart Neovim for changes to take effect.",
				vim.log.levels.WARN
			)
		end)
	end

	if failed_any then
		for _, r in ipairs(results) do
			if not r.applied and r.reason and r.reason ~= "already_patched" then
				vim.schedule(function()
					vim.notify(
						string.format("[pyworks] Molten patch '%s' failed: %s", r.name, r.reason),
						vim.log.levels.ERROR
					)
				end)
			end
		end
	end

	return patched_any, results
end

return M
