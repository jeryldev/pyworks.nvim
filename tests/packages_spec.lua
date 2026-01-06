-- Test suite for pyworks.core.packages module
-- Tests import detection and package mapping

local packages = require("pyworks.core.packages")

describe("packages", function()
	describe("scan_imports", function()
		it("should extract package names from simple imports", function()
			local temp_file = vim.fn.tempname() .. ".py"
			vim.fn.writefile({
				"import os",
				"import json",
				"import numpy",
			}, temp_file)

			local imports = packages.scan_imports(temp_file, "python")

			assert.is_true(vim.tbl_contains(imports, "os"))
			assert.is_true(vim.tbl_contains(imports, "json"))
			assert.is_true(vim.tbl_contains(imports, "numpy"))

			vim.fn.delete(temp_file)
		end)

		it("should NOT extract alias names from 'import X as Y'", function()
			local temp_file = vim.fn.tempname() .. ".py"
			vim.fn.writefile({
				"import numpy as np",
				"import pandas as pd",
				"import matplotlib.pyplot as plt",
			}, temp_file)

			local imports = packages.scan_imports(temp_file, "python")

			-- Should have the package names
			assert.is_true(vim.tbl_contains(imports, "numpy"))
			assert.is_true(vim.tbl_contains(imports, "pandas"))
			assert.is_true(vim.tbl_contains(imports, "matplotlib"))

			-- Should NOT have the aliases
			assert.is_false(vim.tbl_contains(imports, "np"))
			assert.is_false(vim.tbl_contains(imports, "pd"))
			assert.is_false(vim.tbl_contains(imports, "plt"))

			vim.fn.delete(temp_file)
		end)

		it("should handle comma-separated imports with aliases", function()
			local temp_file = vim.fn.tempname() .. ".py"
			vim.fn.writefile({
				"import os, sys, json",
				"import numpy as np, pandas as pd",
			}, temp_file)

			local imports = packages.scan_imports(temp_file, "python")

			-- Should have the package names
			assert.is_true(vim.tbl_contains(imports, "os"))
			assert.is_true(vim.tbl_contains(imports, "sys"))
			assert.is_true(vim.tbl_contains(imports, "json"))
			assert.is_true(vim.tbl_contains(imports, "numpy"))
			assert.is_true(vim.tbl_contains(imports, "pandas"))

			-- Should NOT have the aliases
			assert.is_false(vim.tbl_contains(imports, "np"))
			assert.is_false(vim.tbl_contains(imports, "pd"))

			vim.fn.delete(temp_file)
		end)

		it("should extract package from 'from X import Y'", function()
			local temp_file = vim.fn.tempname() .. ".py"
			vim.fn.writefile({
				"from collections import defaultdict",
				"from pathlib import Path",
				"from sklearn.model_selection import train_test_split",
			}, temp_file)

			local imports = packages.scan_imports(temp_file, "python")

			assert.is_true(vim.tbl_contains(imports, "collections"))
			assert.is_true(vim.tbl_contains(imports, "pathlib"))
			assert.is_true(vim.tbl_contains(imports, "sklearn"))

			vim.fn.delete(temp_file)
		end)

		it("should skip relative imports", function()
			local temp_file = vim.fn.tempname() .. ".py"
			vim.fn.writefile({
				"from . import utils",
				"from .. import config",
				"from .helpers import foo",
				"import numpy",
			}, temp_file)

			local imports = packages.scan_imports(temp_file, "python")

			-- Should NOT have relative imports
			assert.is_false(vim.tbl_contains(imports, "utils"))
			assert.is_false(vim.tbl_contains(imports, "config"))
			assert.is_false(vim.tbl_contains(imports, "helpers"))

			-- Should have regular imports
			assert.is_true(vim.tbl_contains(imports, "numpy"))

			vim.fn.delete(temp_file)
		end)

		it("should skip comments", function()
			local temp_file = vim.fn.tempname() .. ".py"
			vim.fn.writefile({
				"# import fake_package",
				"import numpy  # real import",
			}, temp_file)

			local imports = packages.scan_imports(temp_file, "python")

			assert.is_false(vim.tbl_contains(imports, "fake_package"))
			assert.is_true(vim.tbl_contains(imports, "numpy"))

			vim.fn.delete(temp_file)
		end)
	end)

	describe("map_import_to_package", function()
		it("should map common aliases to package names", function()
			assert.equals("scikit-learn", packages.map_import_to_package("sklearn", "python"))
			assert.equals("opencv-python", packages.map_import_to_package("cv2", "python"))
			assert.equals("Pillow", packages.map_import_to_package("PIL", "python"))
			assert.equals("beautifulsoup4", packages.map_import_to_package("bs4", "python"))
		end)

		it("should return same name if no mapping exists", function()
			assert.equals("numpy", packages.map_import_to_package("numpy", "python"))
			assert.equals("pandas", packages.map_import_to_package("pandas", "python"))
		end)
	end)

	describe("is_stdlib", function()
		it("should recognize standard library modules", function()
			assert.is_true(packages.is_stdlib("os", "python"))
			assert.is_true(packages.is_stdlib("sys", "python"))
			assert.is_true(packages.is_stdlib("json", "python"))
			assert.is_true(packages.is_stdlib("collections", "python"))
			assert.is_true(packages.is_stdlib("pathlib", "python"))
			assert.is_true(packages.is_stdlib("asyncio", "python"))
		end)

		it("should not recognize third-party packages as stdlib", function()
			assert.is_false(packages.is_stdlib("numpy", "python"))
			assert.is_false(packages.is_stdlib("pandas", "python"))
			assert.is_false(packages.is_stdlib("requests", "python"))
		end)
	end)

	describe("is_custom_package", function()
		it("should recognize test modules as custom", function()
			assert.is_true(packages.is_custom_package("test_utils", "python"))
			assert.is_true(packages.is_custom_package("utils_test", "python"))
			assert.is_true(packages.is_custom_package("conftest", "python"))
		end)

		it("should recognize private modules as custom", function()
			assert.is_true(packages.is_custom_package("_internal", "python"))
		end)

		it("should not flag regular packages as custom", function()
			assert.is_false(packages.is_custom_package("numpy", "python"))
			assert.is_false(packages.is_custom_package("pandas", "python"))
		end)
	end)
end)
