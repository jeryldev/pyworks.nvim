describe("cell_engine", function()
    local cell_engine

    before_each(function()
        package.loaded["pyworks.core.cell_engine"] = nil
        cell_engine = require("pyworks.core.cell_engine")
    end)

    describe("find_cell_boundaries", function()
        it("should find cell start and end from cursor position", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "import numpy as np",
                "x = 1",
                "# %%",
                "y = 2",
            })

            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            local start_line, end_line = cell_engine.find_cell_boundaries()

            assert.equals(2, start_line)
            assert.equals(3, end_line)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)

        it("should handle last cell extending to end of file", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
                "# %%",
                "y = 2",
                "z = 3",
            })

            vim.api.nvim_win_set_cursor(0, { 4, 0 })
            local start_line, end_line = cell_engine.find_cell_boundaries()

            assert.equals(4, start_line)
            assert.equals(5, end_line)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)

        it("should return nil for empty cell", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "# %%",
            })

            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            local start_line, end_line = cell_engine.find_cell_boundaries()

            assert.is_nil(start_line)
            assert.is_nil(end_line)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)
    end)

    describe("count_cells", function()
        it("should count all cell markers in buffer", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
                "# %%",
                "y = 2",
                "# %% [markdown]",
                "# Some text",
            })

            local count = cell_engine.count_cells(bufnr)
            assert.equals(3, count)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)

        it("should return 0 for buffer with no cells", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "x = 1",
                "y = 2",
            })

            local count = cell_engine.count_cells(bufnr)
            assert.equals(0, count)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)
    end)

    describe("get_cell_positions", function()
        it("should return line numbers of all cell markers", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
                "# %%",
                "y = 2",
                "# %%",
                "z = 3",
            })

            local positions = cell_engine.get_cell_positions(bufnr)
            assert.same({ 1, 3, 5 }, positions)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)
    end)

    describe("is_markdown_cell", function()
        it("should detect markdown cells", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %% [markdown]",
                "# Some text",
                "# %%",
                "x = 1",
            })

            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            assert.is_true(cell_engine.is_markdown_cell())

            vim.api.nvim_win_set_cursor(0, { 4, 0 })
            assert.is_false(cell_engine.is_markdown_cell())

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)
    end)

    describe("get_cell_pattern", function()
        it("should return default pattern", function()
            local pattern = cell_engine.get_cell_pattern()
            assert.equals("^# %%%%", pattern)
        end)
    end)
end)
