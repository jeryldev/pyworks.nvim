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

    describe("navigation", function()
        it("next_cell should move cursor past the next marker", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
                "# %%",
                "y = 2",
            })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })

            local found = cell_engine.next_cell()
            assert.is_true(found)

            local cursor = vim.api.nvim_win_get_cursor(0)
            assert.equals(4, cursor[1])

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)

        it("next_cell should return false at last cell", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
            })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })

            local found = cell_engine.next_cell()
            assert.is_false(found)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)

        it("prev_cell should move to the previous cell content", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
                "# %%",
                "y = 2",
            })
            vim.api.nvim_win_set_cursor(0, { 4, 0 })

            local found = cell_engine.prev_cell()
            assert.is_true(found)

            local cursor = vim.api.nvim_win_get_cursor(0)
            assert.equals(2, cursor[1])

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)
    end)

    describe("cell insertion", function()
        it("insert_cell_below should add a cell marker after current cell", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
            })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })

            cell_engine.insert_cell_below()

            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local count = 0
            for _, line in ipairs(lines) do
                if line:match("^# %%") then count = count + 1 end
            end
            assert.equals(2, count)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)

        it("insert_cell_above should add a cell marker before current cell", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
            })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })

            cell_engine.insert_cell_above()

            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local count = 0
            for _, line in ipairs(lines) do
                if line:match("^# %%") then count = count + 1 end
            end
            assert.equals(2, count)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)
    end)

    describe("cell operations", function()
        it("toggle_cell_type should switch code to markdown", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
            })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })

            local toggled = cell_engine.toggle_cell_type()
            assert.is_true(toggled)

            local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
            assert.equals("# %% [markdown]", first_line)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)

        it("toggle_cell_type should switch markdown to code", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %% [markdown]",
                "# Some text",
            })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })

            cell_engine.toggle_cell_type()

            local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
            assert.equals("# %%", first_line)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)

        it("merge_cell_below should remove next marker", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
                "# %%",
                "y = 2",
            })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })

            local merged = cell_engine.merge_cell_below()
            assert.is_true(merged)

            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local count = 0
            for _, line in ipairs(lines) do
                if line:match("^# %%") then count = count + 1 end
            end
            assert.equals(1, count)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)

        it("split_cell should insert marker at cursor", function()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "# %%",
                "x = 1",
                "y = 2",
            })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })

            cell_engine.split_cell()

            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local count = 0
            for _, line in ipairs(lines) do
                if line:match("^# %%") then count = count + 1 end
            end
            assert.equals(2, count)

            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)
    end)
end)
