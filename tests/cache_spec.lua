describe("cache", function()
	local cache_module

	before_each(function()
		package.loaded["pyworks.core.cache"] = nil
		cache_module = require("pyworks.core.cache")
	end)

	describe("basic operations", function()
		it("should store and retrieve values", function()
			cache_module.set("test_key", "test_value")
			assert.are.equal("test_value", cache_module.get("test_key"))
		end)

		it("should return nil for missing keys", function()
			assert.is_nil(cache_module.get("nonexistent"))
		end)

		it("should invalidate keys", function()
			cache_module.set("test_key", true)
			assert.is_true(cache_module.get("test_key"))
			cache_module.invalidate("test_key")
			assert.is_nil(cache_module.get("test_key"))
		end)
	end)

	describe("custom TTL", function()
		it("should accept optional TTL parameter without error", function()
			assert.has_no.errors(function()
				cache_module.set("test_key", "value", 120)
			end)
			assert.are.equal("value", cache_module.get("test_key"))
		end)
	end)

	describe("invalidation correctness", function()
		it("should invalidate jupytext_installed key", function()
			cache_module.set("jupytext_installed", true)
			assert.is_true(cache_module.get("jupytext_installed"))
			cache_module.invalidate("jupytext_installed")
			assert.is_nil(cache_module.get("jupytext_installed"))
		end)

		it("should invalidate patterns", function()
			cache_module.set("installed_packages_python", { "numpy" })
			cache_module.set("installed_packages_r", { "ggplot2" })
			cache_module.invalidate_pattern("installed_packages_")
			assert.is_nil(cache_module.get("installed_packages_python"))
			assert.is_nil(cache_module.get("installed_packages_r"))
		end)
	end)

	describe("stats", function()
		it("should report correct counts", function()
			cache_module.set("key1", "val1")
			cache_module.set("key2", "val2")
			local stats = cache_module.stats()
			assert.are.equal(2, stats.total)
			assert.are.equal(2, stats.active)
			assert.are.equal(0, stats.expired)
		end)
	end)

	-- F4a: M.get honours entry.ttl but M.stats ignored it, so entries created
	-- with an explicit TTL were mis-classified - and :PyworksDiagnostics reports
	-- those numbers.
	describe("stats", function()
		it("should honour a per-entry TTL over the key's default", function()
			cache_module.invalidate_pattern(".*")
			-- jupytext_installed defaults to an hour, so this entry counts as
			-- expired only if the explicit TTL is the one being applied
			cache_module.set("jupytext_installed_probe", "v", -1)
			cache_module.set("jupytext_installed_other", "v", 3600)

			local stats = cache_module.stats()

			assert.are.equal(2, stats.total)
			assert.are.equal(1, stats.expired)
			assert.are.equal(1, stats.active)
		end)
	end)

	-- F4b: a typo in the cache config was silently dropped, unlike
	-- validate_config which warns on type errors
	describe("configure", function()
		it("should apply a known TTL key", function()
			cache_module.configure({ kernel_list = 12345 })
			cache_module.set("kernel_list_probe", "v")

			assert.are.equal("v", cache_module.get("kernel_list_probe"))
			cache_module.configure({ kernel_list = 60 })
		end)

		it("should warn about an unknown key instead of ignoring it", function()
			local warned = false
			local real = vim.notify
			vim.notify = function(msg, level)
				if level == vim.log.levels.WARN and tostring(msg):find("kernal_list", 1, true) then
					warned = true
				end
			end

			cache_module.configure({ kernal_list = 60 })

			vim.notify = real
			assert.is_true(warned)
		end)
	end)
end)
