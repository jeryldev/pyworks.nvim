-- Zero-dependency line coverage for pyworks specs
--
-- luacov is the usual answer, but luarocks on a typical macOS box targets Lua
-- 5.5 while Neovim runs LuaJIT (5.1), so an installed rock lands in a tree
-- Neovim cannot load. This uses debug.sethook instead: nothing to install, and
-- the local run and CI execute exactly the same code.
--
-- The suite spawns one child Neovim per spec file, so each child dumps its hits
-- to $PYWORKS_COVERAGE_DIR and a merge step aggregates them - the same
-- stats-file model luacov uses.

local M = {}

local hits = {}
local active = false

-- Absolute path of the source, or nil if it is not one of ours.
--
-- Sources arrive in whichever form package.path matched: the suite's child
-- processes resolve modules through the default "./?.lua" entry and report
-- "./lua/pyworks/...", while a direct run reports the absolute path. Recording
-- both forms as different keys made every module read 0%.
local cwd = nil
local resolved = {}

local function source_path(info)
	if not info or not info.source or info.source:sub(1, 1) ~= "@" then
		return nil
	end

	local raw = info.source:sub(2)
	local cached = resolved[raw]
	if cached ~= nil then
		return cached or nil
	end

	local absolute = nil
	if raw:find("lua/pyworks/", 1, true) then
		if raw:sub(1, 1) == "/" then
			absolute = raw
		else
			absolute = (cwd or ".") .. "/" .. raw:gsub("^%./", "")
		end
	end

	resolved[raw] = absolute or false
	return absolute
end

local function hook(_, line)
	local path = source_path(debug.getinfo(2, "S"))
	if path then
		local file = hits[path]
		if not file then
			file = {}
			hits[path] = file
		end
		file[line] = true
	end
end

function M.start()
	if active then
		return
	end
	active = true
	cwd = vim.uv.cwd()
	debug.sethook(hook, "l")

	-- debug.sethook applies to the current coroutine only, and plenary's busted
	-- runs every test inside one - without this the hook never fires for the
	-- code under test and every module reports 0%. luacov patches these two
	-- functions for the same reason.
	local create, wrap = coroutine.create, coroutine.wrap

	coroutine.create = function(fn)
		return create(function(...)
			debug.sethook(hook, "l")
			return fn(...)
		end)
	end

	coroutine.wrap = function(fn)
		return wrap(function(...)
			debug.sethook(hook, "l")
			return fn(...)
		end)
	end
end

function M.stop()
	if not active then
		return
	end
	debug.sethook()
	active = false
end

function M.hits()
	return hits
end

-- Append this process's hits to the shared directory
function M.dump(dir)
	M.stop()
	if vim.fn.isdirectory(dir) == 0 then
		pcall(vim.fn.mkdir, dir, "p")
	end

	local out = {}
	for path, lines in pairs(hits) do
		local list = {}
		for line in pairs(lines) do
			table.insert(list, line)
		end
		table.sort(list)
		out[path] = list
	end

	local ok, encoded = pcall(vim.json.encode, out)
	if not ok then
		return false
	end

	local target = string.format("%s/%d-%d.json", dir, vim.uv.os_getpid(), math.floor(vim.uv.hrtime() % 1e6))
	local file = io.open(target, "w")
	if not file then
		return false
	end
	file:write(encoded)
	file:close()
	return true
end

-- Lines that could plausibly be executed: used as the denominator. Blank lines,
-- comments and block terminators are excluded. This is an approximation - it is
-- meant to expose modules with *no* coverage, not to certify a precise figure.
local function candidate_lines(path)
	local ok, content = pcall(vim.fn.readfile, path)
	if not ok then
		return 0
	end
	local count = 0
	for _, line in ipairs(content) do
		local trimmed = vim.trim(line)
		local skip = trimmed == ""
			or trimmed:match("^%-%-")
			or trimmed == "end"
			or trimmed == "end)"
			or trimmed == "end,"
			or trimmed == "else"
			or trimmed == "})"
			or trimmed == "}"
			or trimmed == "{"
		if not skip then
			count = count + 1
		end
	end
	return count
end

-- Merge every dumped file and return { [module] = { executed, candidates, pct } }
function M.merge(dir)
	local merged = {}

	for _, file in ipairs(vim.fn.glob(dir .. "/*.json", false, true)) do
		local ok, content = pcall(vim.fn.readfile, file)
		if ok then
			local decoded_ok, decoded = pcall(vim.json.decode, table.concat(content, "\n"))
			if decoded_ok and type(decoded) == "table" then
				for path, lines in pairs(decoded) do
					merged[path] = merged[path] or {}
					for _, line in ipairs(lines) do
						merged[path][line] = true
					end
				end
			end
		end
	end

	-- Every module under lua/pyworks, including ones never loaded at all -
	-- those are the gaps worth seeing
	local report = {}
	for _, path in ipairs(vim.fn.glob("lua/pyworks/**/*.lua", false, true)) do
		local abs = vim.fn.fnamemodify(path, ":p")
		local executed = 0
		for _ in pairs(merged[abs] or {}) do
			executed = executed + 1
		end
		local candidates = candidate_lines(path)
		report[path:gsub("^lua/pyworks/", "")] = {
			executed = executed,
			candidates = candidates,
			-- clamped: candidate_lines is a heuristic denominator, so a module
			-- can execute more lines than it estimates
			pct = candidates > 0 and math.min(100, math.floor(executed / candidates * 100)) or 0,
		}
	end

	return report
end

function M.format_report(report)
	local names = {}
	for name in pairs(report) do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		return report[a].pct < report[b].pct
	end)

	local lines = { string.format("%-38s %8s %8s %6s", "module", "executed", "lines", "cov"), string.rep("-", 64) }
	local total_exec, total_cand = 0, 0
	for _, name in ipairs(names) do
		local entry = report[name]
		total_exec = total_exec + entry.executed
		total_cand = total_cand + entry.candidates
		table.insert(lines, string.format("%-38s %8d %8d %5d%%", name, entry.executed, entry.candidates, entry.pct))
	end
	table.insert(lines, string.rep("-", 64))
	table.insert(
		lines,
		string.format(
			"%-38s %8d %8d %5d%%",
			"TOTAL",
			total_exec,
			total_cand,
			total_cand > 0 and math.floor(total_exec / total_cand * 100) or 0
		)
	)
	return table.concat(lines, "\n")
end

return M
