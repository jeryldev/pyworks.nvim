local patches = require("pyworks.molten_patches")

describe("molten_patches", function()
	local temp_dir

	before_each(function()
		temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir .. "/rplugin/python3/molten", "p")
	end)

	after_each(function()
		vim.fn.delete(temp_dir, "rf")
	end)

	describe("patch_moltenbuffer", function()
		local unpatched_content = [[
    def tick(self):
        if self.options.virt_text_output:
            for span, output in self.outputs.items():
                output.show_virtual_output(span.end)

        self.canvas.present()
]]

		local function write_moltenbuffer(content)
			local path = temp_dir .. "/rplugin/python3/molten/moltenbuffer.py"
			vim.fn.writefile(vim.split(content, "\n"), path)
		end

		it("patches unpatched moltenbuffer.py", function()
			write_moltenbuffer(unpatched_content)

			local ok, err = patches.patch_moltenbuffer(temp_dir)
			assert.is_true(ok)
			assert.is_nil(err)

			local result = patches.read_file(temp_dir .. "/rplugin/python3/molten/moltenbuffer.py")
			assert.truthy(result:find("list(self.outputs.items())", 1, true))
			assert.falsy(result:find("for span, output in self.outputs.items():", 1, true))
		end)

		it("skips already-patched file", function()
			local patched = unpatched_content:gsub(
				"for span, output in self%.outputs%.items%(%):",
				"for span, output in list(self.outputs.items()):"
			)
			write_moltenbuffer(patched)

			local ok, err = patches.patch_moltenbuffer(temp_dir)
			assert.is_false(ok)
			assert.equals("already_patched", err)
		end)

		it("is idempotent when applied twice", function()
			write_moltenbuffer(unpatched_content)

			patches.patch_moltenbuffer(temp_dir)
			local content_after_first = patches.read_file(temp_dir .. "/rplugin/python3/molten/moltenbuffer.py")

			local ok, err = patches.patch_moltenbuffer(temp_dir)
			assert.is_false(ok)
			assert.equals("already_patched", err)

			local content_after_second = patches.read_file(temp_dir .. "/rplugin/python3/molten/moltenbuffer.py")
			assert.equals(content_after_first, content_after_second)
		end)

		it("returns error when file not found", function()
			local ok, err = patches.patch_moltenbuffer(temp_dir .. "/nonexistent")
			assert.is_false(ok)
			assert.truthy(err:find("not found"))
		end)
	end)

	describe("patch_molten_tick", function()
		local unpatched_content = [[
    def function_on_exit_pre(self, _: Any) -> None:
        self._deinitialize()

    @pynvim.function("MoltenTick", sync=True)  # type: ignore
    @nvimui  # type: ignore
    def function_molten_tick(self, _: Any) -> None:
        self._initialize_if_necessary()

        molten_kernels = self._get_current_buf_kernels(False)
        if molten_kernels is None:
            return

        for m in molten_kernels:
            m.tick()

    @pynvim.function("MoltenTickInput", sync=False)  # type: ignore
]]

		local function write_init(content)
			local path = temp_dir .. "/rplugin/python3/molten/__init__.py"
			vim.fn.writefile(vim.split(content, "\n"), path)
		end

		it("patches unpatched __init__.py", function()
			write_init(unpatched_content)

			local ok, err = patches.patch_molten_tick(temp_dir)
			assert.is_true(ok)
			assert.is_nil(err)

			local result = patches.read_file(temp_dir .. "/rplugin/python3/molten/__init__.py")
			assert.truthy(result:find("_ticking", 1, true))
			assert.truthy(result:find("self._ticking = True", 1, true))
			assert.truthy(result:find("finally:", 1, true))
		end)

		it("skips already-patched file", function()
			local patched = "_ticking = False\n" .. unpatched_content
			write_init(patched)

			local ok, err = patches.patch_molten_tick(temp_dir)
			assert.is_false(ok)
			assert.equals("already_patched", err)
		end)

		it("is idempotent when applied twice", function()
			write_init(unpatched_content)

			patches.patch_molten_tick(temp_dir)
			local content_after_first = patches.read_file(temp_dir .. "/rplugin/python3/molten/__init__.py")

			local ok, err = patches.patch_molten_tick(temp_dir)
			assert.is_false(ok)
			assert.equals("already_patched", err)

			local content_after_second = patches.read_file(temp_dir .. "/rplugin/python3/molten/__init__.py")
			assert.equals(content_after_first, content_after_second)
		end)

		it("returns error when file not found", function()
			local ok, err = patches.patch_molten_tick(temp_dir .. "/nonexistent")
			assert.is_false(ok)
			assert.truthy(err:find("not found"))
		end)
	end)

	describe("read_file / write_file", function()
		it("round-trips content correctly", function()
			local path = temp_dir .. "/test.txt"
			local content = "hello\nworld\n"

			assert.is_true(patches.write_file(path, content))
			assert.equals(content, patches.read_file(path))
		end)

		it("returns nil for nonexistent file", function()
			assert.is_nil(patches.read_file(temp_dir .. "/nonexistent.txt"))
		end)

		it("returns false when writing to invalid path", function()
			assert.is_false(patches.write_file(temp_dir .. "/no/such/dir/file.txt", "content"))
		end)
	end)
end)
