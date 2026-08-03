-- Test suite for the Jupyter runtime directory Molten writes into
--
-- Molten does not ask jupyter_core where transient files belong. After starting
-- a kernel it overwrites the connection file path by hand:
--
--     self.kernel_client.connection_file =
--         f"{self.kernel_client.data_dir}/runtime/kernel-{kernel_id}.json"
--     self.kernel_client.write_connection_file()
--
-- write_connection_file() does not create the directory. When
-- <jupyter data dir>/runtime is missing the call raises ENOENT inside the
-- rplugin host, so :MoltenInit fails *asynchronously* - vim.cmd returns
-- success, pyworks marks the buffer initialised, and no kernel ever exists.
-- Every cell then sits on "* On Hold" with no error (issue #10).
--
-- Note this is NOT the same path as jupyter_runtime_dir(): that honours
-- JUPYTER_RUNTIME_DIR, Molten never does. We must create the directory Molten
-- actually writes to, not the one jupyter_client would pick.

local detector = require("pyworks.core.detector")

describe("molten runtime directory", function()
	local saved = {}

	local function set_env(name, value)
		saved[name] = saved[name] or { vim.env[name] }
		vim.env[name] = value
	end

	after_each(function()
		for name, original in pairs(saved) do
			vim.env[name] = original[1]
		end
		saved = {}
	end)

	describe("jupyter_data_dir", function()
		it("should honour JUPYTER_DATA_DIR when set", function()
			set_env("JUPYTER_DATA_DIR", "/tmp/pyworks-jupyter-data")

			assert.equals("/tmp/pyworks-jupyter-data", detector.jupyter_data_dir())
		end)

		it("should fall back to a platform default", function()
			set_env("JUPYTER_DATA_DIR", nil)

			local dir = detector.jupyter_data_dir()

			assert.is_string(dir)
			assert.is_true(#dir > 0)
			-- an absolute path, not a bare "~" that Molten could not resolve
			assert.equals("/", dir:sub(1, 1))
		end)
	end)

	describe("molten_runtime_dir", function()
		it("should be the data dir's runtime subdirectory", function()
			set_env("JUPYTER_DATA_DIR", "/tmp/pyworks-jupyter-data")

			assert.equals("/tmp/pyworks-jupyter-data/runtime", detector.molten_runtime_dir())
		end)

		it("should ignore JUPYTER_RUNTIME_DIR, which Molten does not read", function()
			set_env("JUPYTER_DATA_DIR", "/tmp/pyworks-jupyter-data")
			set_env("JUPYTER_RUNTIME_DIR", "/tmp/somewhere-else")

			assert.equals("/tmp/pyworks-jupyter-data/runtime", detector.molten_runtime_dir())
		end)
	end)

	describe("ensure_molten_runtime_dir", function()
		it("should create the directory when it is missing", function()
			local root = vim.fn.tempname()
			set_env("JUPYTER_DATA_DIR", root)
			assert.equals(0, vim.fn.isdirectory(root .. "/runtime"))

			assert.is_true(detector.ensure_molten_runtime_dir())

			assert.equals(1, vim.fn.isdirectory(root .. "/runtime"))
			vim.fn.delete(root, "rf")
		end)

		it("should succeed when the directory already exists", function()
			local root = vim.fn.tempname()
			vim.fn.mkdir(root .. "/runtime", "p")
			set_env("JUPYTER_DATA_DIR", root)

			assert.is_true(detector.ensure_molten_runtime_dir())
			assert.is_true(detector.ensure_molten_runtime_dir())

			vim.fn.delete(root, "rf")
		end)

		it("should report failure instead of throwing when it cannot create", function()
			-- a file where the directory should be: mkdir cannot succeed
			local root = vim.fn.tempname()
			vim.fn.mkdir(root, "p")
			vim.fn.writefile({ "" }, root .. "/runtime")
			set_env("JUPYTER_DATA_DIR", root)

			assert.is_false(detector.ensure_molten_runtime_dir())

			vim.fn.delete(root, "rf")
		end)
	end)
end)
