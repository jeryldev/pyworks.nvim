describe("commands/create", function()
    local create

    before_each(function()
        package.loaded["pyworks.commands.create"] = nil
        create = require("pyworks.commands.create")
    end)

    describe("generate_cell_id", function()
        it("should produce 100 unique IDs without collision", function()
            local ids = {}
            for _ = 1, 100 do
                local id = create.generate_cell_id()
                assert.is_not_nil(id)
                assert.equals(8, #id)
                assert.is_nil(ids[id], "Collision detected: " .. id)
                ids[id] = true
            end
        end)

        it("should produce 8-character alphanumeric IDs", function()
            local id = create.generate_cell_id()
            assert.is_truthy(id:match("^[a-z0-9]+$"))
            assert.equals(8, #id)
        end)
    end)

    describe("get_python_version", function()
        it("should return a version string matching X.Y.Z format", function()
            local version = create.get_python_version()
            assert.is_not_nil(version)
            assert.is_truthy(version:match("^%d+%.%d+%.%d+$"),
                "Expected X.Y.Z format, got: " .. version)
        end)

        it("should match system python3 version when available", function()
            if vim.fn.executable("python3") == 0 then
                pending("python3 not available")
                return
            end
            local version = create.get_python_version()
            local utils = require("pyworks.utils")
            local success, output, _ = utils.system_with_timeout("python3 --version 2>&1", 5000)
            if success then
                local system_version = output:match("Python (%d+%.%d+%.%d+)")
                if system_version then
                    assert.equals(system_version, version)
                end
            end
        end)
    end)
end)
