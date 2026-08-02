-- Test suite for PEP 503 package-name normalisation
--
-- E1. Python distribution names use hyphens where import names use underscores,
-- and the installed-package list was compared case-folded but separator-naive.
-- Verified before the fix, on a healthy environment:
--   installed list contains 'jupyter-client':  true
--   installed list contains 'jupyter_client':  false
--   detect_missing_packages says missing:      { "jupyter_client" }
--   is_package_installed('jupyter_client'):    true   (import probe)
--
-- So a file containing `import jupyter_client` was told the package was missing
-- on every scan, forever, and offered to install what was already there.

local packages = require("pyworks.core.packages")

describe("package name normalisation", function()
	describe("normalize_package_name", function()
		it("should treat underscores and hyphens as equivalent", function()
			assert.are.equal(
				packages.normalize_package_name("jupyter_client"),
				packages.normalize_package_name("jupyter-client")
			)
		end)

		it("should treat dots as separators too", function()
			assert.are.equal(
				packages.normalize_package_name("ruamel.yaml"),
				packages.normalize_package_name("ruamel-yaml")
			)
		end)

		it("should fold case", function()
			assert.are.equal(packages.normalize_package_name("PyYAML"), packages.normalize_package_name("pyyaml"))
		end)

		it("should collapse runs of separators", function()
			assert.are.equal(
				packages.normalize_package_name("backports__zoneinfo"),
				packages.normalize_package_name("backports-zoneinfo")
			)
		end)

		it("should keep genuinely different names distinct", function()
			assert.are_not.equal(
				packages.normalize_package_name("jupyter-core"),
				packages.normalize_package_name("jupyter-client")
			)
		end)

		it("should handle nil and empty input", function()
			assert.are.equal("", packages.normalize_package_name(nil))
			assert.are.equal("", packages.normalize_package_name(""))
		end)
	end)

	describe("detect_missing_packages", function()
		local helpers = require("helpers.project")
		local project

		before_each(function()
			project = helpers.temp_project({ fake_venv = true })
		end)

		after_each(function()
			project.cleanup()
		end)

		-- The reproduction from the audit, as a test
		it("should not report an installed package as missing across separators", function()
			vim.fn.writefile({ "import jupyter_client" }, project.file)
			local python = require("pyworks.languages.python")
			local original = python.get_installed_packages
			python.get_installed_packages = function()
				return { "jupyter-client", "numpy" }
			end

			local missing = packages.detect_missing_packages(project.file, "python")

			python.get_installed_packages = original
			assert.are.same({}, missing)
		end)

		it("should still report a genuinely absent package", function()
			vim.fn.writefile({ "import nonexistentpkg" }, project.file)
			local python = require("pyworks.languages.python")
			local original = python.get_installed_packages
			python.get_installed_packages = function()
				return { "jupyter-client" }
			end

			local missing = packages.detect_missing_packages(project.file, "python")

			python.get_installed_packages = original
			assert.are.same({ "nonexistentpkg" }, missing)
		end)
	end)
end)
