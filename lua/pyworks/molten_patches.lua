local M = {}

local function get_molten_path()
	local lazy_ok, lazy = pcall(require, "lazy.core.config")
	if lazy_ok and lazy.plugins and lazy.plugins["molten-nvim"] then
		local plugin = lazy.plugins["molten-nvim"]
		if plugin.dir then
			return plugin.dir
		end
	end
	return vim.fn.stdpath("data") .. "/lazy/molten-nvim"
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*all")
	f:close()
	return content
end

local function write_file(path, content)
	local f = io.open(path, "w")
	if not f then
		return false
	end
	f:write(content)
	f:close()
	return true
end

function M.apply_patches()
	local molten_dir = get_molten_path()
	local patched_any = false

	local moltenbuffer_path = molten_dir .. "/rplugin/python3/molten/moltenbuffer.py"
	local content = read_file(moltenbuffer_path)
	if content then
		if content:find("for span, output in self.outputs.items():", 1, true) then
			local patched = content:gsub(
				"for span, output in self%.outputs%.items%(%):",
				"for span, output in list(self.outputs.items()):"
			)
			if patched ~= content then
				write_file(moltenbuffer_path, patched)
				patched_any = true
			end
		end
	end

	local init_path = molten_dir .. "/rplugin/python3/molten/__init__.py"
	content = read_file(init_path)
	if content then
		if not content:find("_ticking", 1, true) then
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
			if count > 0 then
				write_file(init_path, patched)
				patched_any = true
			end
		end
	end

	return patched_any
end

return M
