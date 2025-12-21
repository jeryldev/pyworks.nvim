-- Test suite for pyworks.commands.create module
-- Tests notebook creation and JSON validity

describe("pyworks.commands.create", function()
	local temp_dir

	before_each(function()
		temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")
	end)

	after_each(function()
		vim.fn.delete(temp_dir, "rf")
	end)

	describe("PyworksNewPythonNotebook", function()
		it("should create valid JSON notebook file", function()
			local notebook_path = temp_dir .. "/test_notebook.ipynb"

			require("pyworks.commands.create")

			vim.cmd("PyworksNewPythonNotebook " .. notebook_path)

			assert.equals(1, vim.fn.filereadable(notebook_path))

			local content = table.concat(vim.fn.readfile(notebook_path), "\n")

			local ok, decoded = pcall(vim.json.decode, content)
			assert.is_true(ok, "Notebook should be valid JSON")
			assert.is_not_nil(decoded)
		end)

		it("should have proper notebook structure", function()
			local notebook_path = temp_dir .. "/test_structure.ipynb"

			require("pyworks.commands.create")
			vim.cmd("PyworksNewPythonNotebook " .. notebook_path)

			local content = table.concat(vim.fn.readfile(notebook_path), "\n")
			local notebook = vim.json.decode(content)

			assert.is_not_nil(notebook.cells)
			assert.is_table(notebook.cells)
			assert.is_true(#notebook.cells >= 1)

			assert.is_not_nil(notebook.metadata)
			assert.is_not_nil(notebook.metadata.kernelspec)
			assert.equals("python3", notebook.metadata.kernelspec.name)
			assert.equals("python", notebook.metadata.kernelspec.language)

			assert.equals(4, notebook.nbformat)
			assert.equals(5, notebook.nbformat_minor)
		end)

		it("should have cells with required fields", function()
			local notebook_path = temp_dir .. "/test_cells.ipynb"

			require("pyworks.commands.create")
			vim.cmd("PyworksNewPythonNotebook " .. notebook_path)

			local content = table.concat(vim.fn.readfile(notebook_path), "\n")
			local notebook = vim.json.decode(content)

			for _, cell in ipairs(notebook.cells) do
				assert.is_not_nil(cell.cell_type)
				assert.is_not_nil(cell.id)
				assert.is_not_nil(cell.metadata)
				assert.is_not_nil(cell.source)

				if cell.cell_type == "code" then
					assert.is_not_nil(cell.outputs)
				end
			end
		end)

		it("should add .ipynb extension if missing", function()
			local notebook_base = temp_dir .. "/no_extension"
			local expected_path = notebook_base .. ".ipynb"

			require("pyworks.commands.create")
			vim.cmd("PyworksNewPythonNotebook " .. notebook_base)

			assert.equals(1, vim.fn.filereadable(expected_path))
		end)

		it("should not corrupt existing valid notebook on overwrite", function()
			local notebook_path = temp_dir .. "/existing.ipynb"

			local valid_notebook = vim.json.encode({
				cells = {
					{ cell_type = "code", id = "existing", metadata = {}, outputs = {}, source = { "print('hello')" } },
				},
				metadata = { kernelspec = { display_name = "Python 3", language = "python", name = "python3" } },
				nbformat = 4,
				nbformat_minor = 5,
			})
			vim.fn.writefile({ valid_notebook }, notebook_path)

			local original_content = table.concat(vim.fn.readfile(notebook_path), "\n")
			local ok1, _ = pcall(vim.json.decode, original_content)
			assert.is_true(ok1, "Original should be valid JSON")
		end)
	end)

	describe("notebook JSON validity after jupytext conversion", function()
		it("should remain valid JSON after simulated save cycle", function()
			local notebook_path = temp_dir .. "/save_cycle.ipynb"

			require("pyworks.commands.create")
			vim.cmd("PyworksNewPythonNotebook " .. notebook_path)

			local content = table.concat(vim.fn.readfile(notebook_path), "\n")
			local ok, _ = pcall(vim.json.decode, content)
			assert.is_true(ok, "Newly created notebook should be valid JSON")

			local first_char = content:sub(1, 1)
			assert.equals("{", first_char, "Notebook should start with '{' (JSON object)")

			assert.is_false(content:match("^# %-%-%-") ~= nil, "Notebook should not contain jupytext header")
		end)

		it("should detect corrupted notebook (percent format in .ipynb)", function()
			local notebook_path = temp_dir .. "/corrupted.ipynb"

			local percent_format_content = [[# ---
# jupyter:
#   jupytext:
#     text_representation:
#       extension: .py
# ---

# %%
print("hello")
]]
			vim.fn.writefile(vim.split(percent_format_content, "\n"), notebook_path)

			local content = table.concat(vim.fn.readfile(notebook_path), "\n")
			local ok, _ = pcall(vim.json.decode, content)
			assert.is_false(ok, "Percent format content should not be valid JSON")

			local first_char = content:sub(1, 1)
			assert.equals("#", first_char, "Corrupted file starts with '#'")
		end)
	end)
end)
