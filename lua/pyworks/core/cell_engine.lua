local M = {}

local config = {
    cell_marker = "# %%",
}

function M.configure(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

function M.get_cell_pattern()
    return "^" .. vim.pesc(config.cell_marker)
end

local function vim_search_pattern()
    return "^" .. config.cell_marker
end

function M.find_cell_boundaries()
    local pattern = vim_search_pattern()
    local cell_start = vim.fn.search(pattern, "bcnW")
    local cell_end = vim.fn.search(pattern, "nW")

    local start_line, end_line

    if cell_start == 0 and cell_end == 0 then
        start_line = 1
        end_line = vim.fn.line("$")
    elseif cell_start == 0 then
        start_line = 1
        end_line = cell_end - 1
    elseif cell_end == 0 then
        start_line = cell_start + 1
        end_line = vim.fn.line("$")
    else
        start_line = cell_start + 1
        end_line = cell_end - 1
    end

    if start_line > end_line then
        return nil, nil
    end

    return start_line, end_line
end

function M.count_cells(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local pattern = M.get_cell_pattern()
    local count = 0
    for _, line in ipairs(lines) do
        if line:match(pattern) then
            count = count + 1
        end
    end
    return count
end

function M.get_cell_positions(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local pattern = M.get_cell_pattern()
    local positions = {}
    for i, line in ipairs(lines) do
        if line:match(pattern) then
            table.insert(positions, i)
        end
    end
    return positions
end

function M.is_markdown_cell()
    local pattern = vim_search_pattern()
    local cell_start = vim.fn.search(pattern, "bcnW")
    if cell_start == 0 then
        return false
    end
    local line = vim.fn.getline(cell_start)
    return line:match("%[markdown%]") ~= nil
end

return M
