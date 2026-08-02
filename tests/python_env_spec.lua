-- Test suite for environment setup timing in pyworks.languages.python
-- Covers the two ways :PyworksSetup used to claim success without it being true:
-- the 30s throttle silently skipping the work, and "ready" being announced
-- while the package install was still running in the background.

describe("python environment setup", function()
	local python
	local state

	before_each(function()
		package.loaded["pyworks.languages.python"] = nil
		python = require("pyworks.languages.python")
		state = require("pyworks.core.state")
	end)

	describe("should_check_environment", function()
		it("should allow a check once the throttle window has passed", function()
			state.remove("last_check_python_env_python")

			assert.is_true(python.should_check_environment())
		end)

		it("should throttle a repeat check", function()
			state.set_last_check("python_env", "python")

			assert.is_false(python.should_check_environment())
		end)

		-- :PyworksSetup is an explicit request; a throttle meant to keep file
		-- open cheap must not turn it into a silent no-op that reports success
		it("should run anyway when forced", function()
			state.set_last_check("python_env", "python")

			assert.is_true(python.should_check_environment(true))
		end)
	end)

	-- E2: the missing-set was computed by spawning one `python -c "import X"` per
	-- essential, synchronously - 2,453 ms of blocked UI on every file open even
	-- when everything was already installed. One listing answers the same
	-- question in ~50 ms. Correct only because E1 normalises names first.
	describe("missing_essentials", function()
		local helpers = require("helpers.project")
		local project
		local original_listing

		-- Hermetic: without its own project the import probe falls back to cwd and
		-- consults the repo's venv, which has the very packages under test
		before_each(function()
			project = helpers.temp_project({ fake_venv = true })
			original_listing = python.get_installed_packages
		end)

		after_each(function()
			python.get_installed_packages = original_listing
			project.cleanup()
		end)

		it("should report nothing missing when the listing covers every essential", function()
			python.configure({ essentials = { "jupyter_client", "numpy" } })
			python.get_installed_packages = function()
				return { "jupyter-client", "numpy", "pandas" }
			end

			assert.are.same({}, python.missing_essentials(project.file))
		end)

		it("should report an essential that is neither listed nor importable", function()
			python.configure({ essentials = { "pyworks_definitely_absent_pkg", "numpy" } })
			python.get_installed_packages = function()
				return { "numpy" }
			end

			assert.are.same({ "pyworks_definitely_absent_pkg" }, python.missing_essentials(project.file))
		end)

		it("should match across separators and case", function()
			python.configure({ essentials = { "ruamel.yaml", "PyYAML" } })
			python.get_installed_packages = function()
				return { "ruamel-yaml", "pyyaml" }
			end

			assert.are.same({}, python.missing_essentials(project.file))
		end)

		-- A package can be importable without appearing in the listing: stdlib
		-- modules, editable installs, namespace packages. Reinstalling those on
		-- every check would be worse than the delay this replaces.
		it("should trust an import probe over an absent listing entry", function()
			python.configure({ essentials = { "json" } })
			python.get_installed_packages = function()
				return { "numpy" }
			end

			assert.are.same({}, python.missing_essentials(project.file))
		end)
	end)

	-- Regression net for E2: this path blocked the UI for 2,453 ms on every file
	-- open before one listing replaced eight sequential import probes. Tagged,
	-- because it needs a venv with the real packages.
	describe("performance", function()
		local helpers = require("helpers.project")

		it("should check a complete environment well under 200ms", function()
			if not helpers.env_tests_enabled() then
				pending("set PYWORKS_TEST_ENV=1 (needs a populated venv)")
				return
			end

			local probe = vim.env.PYWORKS_TEST_VENV_PROJECT .. "/probe.py"
			vim.fn.writefile({ "print(1)" }, probe)

			local start = vim.uv.hrtime()
			python.missing_essentials(probe)
			local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

			assert.is_true(elapsed_ms < 200, string.format("took %.0f ms (was 2453 ms before E2)", elapsed_ms))
		end)
	end)

	describe("install_essentials completion", function()
		local project, probe

		-- A self-contained project: a .venv whose python is a symlink to the
		-- real interpreter. Pointing these tests at the repo would make
		-- install_essentials create a venv in the checkout on a machine that has
		-- none (CI), which then changes what later tests observe.
		before_each(function()
			project = vim.fn.tempname()
			vim.fn.mkdir(project .. "/.venv/bin", "p")
			vim.uv.fs_symlink(vim.fn.exepath("python3"), project .. "/.venv/bin/python")
			-- The file must exist: get_project_paths falls back to cwd for an
			-- unreadable path, which would point the whole call at the repo
			probe = project .. "/probe.py"
			vim.fn.writefile({ "print('probe')" }, probe)
			-- "json" is stdlib, so the import check always succeeds and no
			-- install is ever spawned
			python.configure({ essentials = { "json" } })
		end)

		after_each(function()
			vim.fn.delete(project, "rf")
		end)

		it("should report completion when nothing is missing", function()
			local completed = nil

			python.install_essentials(probe, function(ok)
				completed = ok
			end)

			assert.is_true(completed)
		end)

		it("should not require a callback", function()
			local ok = pcall(python.install_essentials, probe)

			assert.is_true(ok)
		end)
	end)
end)
