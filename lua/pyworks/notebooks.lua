-- pyworks.nvim - Notebooks module
-- Handles Jupyter notebook creation

local M = {}

-- Function to get Python version
local function get_python_version()
  local handle = io.popen("python3 -c 'import sys; print(\".\".join(map(str, sys.version_info[:3])))'")
  if handle then
    local version = handle:read("*a"):gsub("\n", "")
    handle:close()
    return version ~= "" and version or "3.11.0"
  end
  return "3.11.0"
end

-- Language-specific metadata
local language_specs = {
  python = {
    kernelspec = {
      display_name = "Python 3",
      language = "python",
      name = "python3",
    },
    language_info = {
      codemirror_mode = {
        name = "ipython",
        version = 3,
      },
      file_extension = ".py",
      mimetype = "text/x-python",
      name = "python",
      nbconvert_exporter = "python",
      pygments_lexer = "ipython3",
      version = get_python_version(),
    },
  },
  julia = {
    kernelspec = {
      display_name = "Julia 1.9",
      language = "julia",
      name = "julia-1.9",
    },
    language_info = {
      file_extension = ".jl",
      mimetype = "application/julia",
      name = "julia",
      version = "1.9.0",
    },
  },
  r = {
    kernelspec = {
      display_name = "R",
      language = "R",
      name = "ir",
    },
    language_info = {
      codemirror_mode = "r",
      file_extension = ".r",
      mimetype = "text/x-r-source",
      name = "R",
      pygments_lexer = "r",
      version = "4.3.0",
    },
  },
}

function M.create_notebook(filename, language)
  language = language or "python"

  -- Define script extensions that match jupytext's expectations
  local script_ext = { python = ".py", julia = ".jl", r = ".r", R = ".r", bash = ".sh" }

  -- Get language-specific metadata or use defaults
  local lang_meta = language_specs[language:lower()]
    or {
      kernelspec = {
        display_name = language,
        language = language,
        name = language,
      },
      language_info = {
        name = language,
      },
    }

  -- Ensure kernelspec has language field for jupytext compatibility
  if not lang_meta.kernelspec.language then
    lang_meta.kernelspec.language = language:lower()
  end

  -- Add jupytext metadata for better compatibility
  lang_meta.jupytext = {
    text_representation = {
      extension = script_ext[language:lower()] or ".py", -- Default to .py if unknown
      format_name = "percent",
      format_version = "1.3",
      jupytext_version = "1.17.2",
    },
  }

  local template = {
    cells = {
      {
        cell_type = "markdown",
        metadata = vim.empty_dict(),
        source = { "# New " .. language:gsub("^%l", string.upper) .. " Notebook\n" },
      },
      {
        cell_type = "code",
        execution_count = vim.NIL,
        metadata = vim.empty_dict(),
        outputs = {},
        source = {},
      },
    },
    metadata = lang_meta,
    nbformat = 4,
    nbformat_minor = 5,
  }

  -- Ensure filename has .ipynb extension
  if not filename:match("%.ipynb$") then
    filename = filename .. ".ipynb"
  end

  -- Ensure we're using absolute path to avoid path issues
  if not filename:match("^/") then
    filename = vim.fn.getcwd() .. "/" .. filename
  end

  -- Manually construct the JSON to ensure proper structure
  local cells_json = {}
  for i, cell in ipairs(template.cells) do
    local cell_json = string.format(
      [[{"cell_type":"%s","metadata":{},%s"source":%s}]],
      cell.cell_type,
      cell.cell_type == "code" and [["execution_count":null,"outputs":[],]] or "",
      vim.json.encode(cell.source)
    )
    table.insert(cells_json, cell_json)
  end

  local metadata_json = vim.json.encode(template.metadata)
  local notebook_json = string.format(
    [[{"cells":[%s],"metadata":%s,"nbformat":%d,"nbformat_minor":%d}]],
    table.concat(cells_json, ","),
    metadata_json,
    template.nbformat,
    template.nbformat_minor
  )

  -- Write the notebook file
  local file = io.open(filename, "w")
  if file then
    file:write(notebook_json)
    file:close()
  else
    vim.notify("Failed to create notebook", vim.log.levels.ERROR)
    return
  end

  -- Open the notebook with error handling
  local ok, err = pcall(vim.cmd, "edit " .. filename)
  if ok then
    vim.notify("Created " .. filename)
  else
    vim.notify("Created notebook but error opening: " .. tostring(err), vim.log.levels.WARN)
  end
end

return M