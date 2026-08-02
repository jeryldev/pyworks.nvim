-- Shared fixtures for pyworks specs
--
-- Every test that touches project detection, venvs or package installation must
-- run against a disposable project. Pointing a spec at the repo once made
-- install_essentials create a .venv inside the checkout on CI (no venv there),
-- which changed what a later integration test observed and turned the suite red
-- for reasons unrelated to the change under test (a1417c2).

local M = {}

-- Create a disposable project directory
--
-- opts.fake_venv  .venv/bin/python symlinked to the real interpreter, enough for
--                 has_venv/get_python_path/import probes without installing
--                 anything (~0 ms instead of ~2 s)
-- opts.markers    extra marker files to create, e.g. { "pyproject.toml" }
--
-- Returns { root, file, venv, python, cleanup }
function M.temp_project(opts)
	opts = opts or {}

	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")

	-- The probe file must exist on disk: utils.get_project_paths falls back to
	-- vim.fn.getcwd() for an unreadable path, which would silently retarget
	-- every call at the repository instead of this fixture.
	local file = root .. "/probe.py"
	vim.fn.writefile({ "print('probe')" }, file)

	for _, marker in ipairs(opts.markers or {}) do
		vim.fn.writefile({ "" }, root .. "/" .. marker)
	end

	local venv = root .. "/.venv"
	local python = venv .. "/bin/python"

	if opts.fake_venv then
		vim.fn.mkdir(venv .. "/bin", "p")
		vim.uv.fs_symlink(vim.fn.exepath("python3"), python)
	end

	return {
		root = root,
		file = file,
		venv = venv,
		python = python,
		cleanup = function()
			vim.fn.delete(root, "rf")
		end,
	}
end

-- Whether environment-level tests (real venv, subprocesses) should run.
-- They are opt-in so the default suite stays fast.
function M.env_tests_enabled()
	local value = vim.env.PYWORKS_TEST_ENV
	return value ~= nil and value ~= "" and value ~= "0"
end

-- Whether live Molten/kernel tests should run.
function M.molten_tests_enabled()
	local value = vim.env.PYWORKS_TEST_MOLTEN
	return value ~= nil and value ~= "" and value ~= "0"
end

return M
