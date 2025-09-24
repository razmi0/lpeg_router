-- luajit test/bench/stress.lua --add4 --lookup1 --dynamic_lookup1
local r = require("lpeg-router").new()
local tx = require("test.lib.tx")

tx.beforeEach = function()
    r = require("lpeg-router").new()
end

---@param type "add" | "lookup" | "dynamic_lookup"
local get_duration_budget = function(type)
    for i = 1, #arg, 1 do
        if arg[i]:match("--" .. type .. "%d+") then
            return tonumber(arg[i]:match("%d+"))
        end
    end
    return 1
end

tx.describe("router-stress-test", function()
    tx.it("should handle adding 5,000 static routes efficiently", function()
        local handler = function() return "ok" end

        local t0 = os.clock()
        for i = 1, 5000 do
            r:add("GET", "/path" .. i, { handler })
        end
        local t1 = os.clock()

        local res = r:search("GET", "/path5000")
        tx.equal(res.status, "found")

        local duration = t1 - t0
        local budget = get_duration_budget("add")
        if duration > budget then
            tx.fail(duration .. "s" .. "/" .. budget .. "s")
        else
            print(duration .. "s" .. "/" .. budget .. "s")
        end
    end)

    tx.it("should handle 100,000 random lookups efficiently", function()
        local handler = function() return "ok" end

        -- preload 500 routes
        for i = 1, 500 do
            r:add("GET", "/lookup" .. i, { handler })
        end

        local t0 = os.clock()
        for i = 1, 100000 do
            local idx = math.random(1, 500)
            local res = r:search("GET", "/lookup" .. idx)
            tx.equal(res.status, "found")
        end
        local t1 = os.clock()

        local duration = t1 - t0
        local budget = get_duration_budget("lookup")
        if duration > budget then
            tx.fail(duration .. "s" .. "/" .. budget .. "s")
        else
            print(duration .. "s" .. "/" .. budget .. "s")
        end
    end)

    tx.it("should handle 100k dynamic lookups", function()
        local handler = function() return "ok" end
        r:add("GET", "/user/:id", { handler })

        local t0 = os.clock()
        for i = 1, 100000 do
            local res = r:search("GET", "/user/" .. i)
            tx.equal(res.status, "found")
            tx.equal(res.params.id, tostring(i))
        end
        local t1 = os.clock()

        local duration = t1 - t0
        local budget = get_duration_budget("dynamic_lookup")
        if duration > budget then
            tx.fail(duration .. "s" .. "/" .. budget .. "s")
        else
            print(duration .. "s" .. "/" .. budget .. "s")
        end
    end)
end)
