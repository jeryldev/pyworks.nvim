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
end)
