-- luajit test/bench/stress.lua --add-1-5000 --lookup-1-100000 --dynamic_lookup-1-100000
local r = require("lpeg-router").new()
local tx = require("test.lib.tx")

tx.beforeEach = function()
    r = require("lpeg-router").new()
end

---@param type "add" | "lookup" | "dynamic_lookup"
local get_rules = function(type)
    for i = 1, #arg, 1 do
        local challenge_duration, challenge_route = arg[i]:match("%-%-" .. type .. "%-(%d+)%-(%d+)")
        if challenge_duration and challenge_route then
            return {
                max_duration = tonumber(challenge_duration), max_routes = tonumber(challenge_route)
            }
        end
    end
    error("Arguments not found --<challenge_duration>-<challenge_route>")
end

local add_rules = get_rules("add")
local lookup_rules = get_rules("lookup")
local dynamic_lookup_rules = get_rules("dynamic_lookup")

tx.describe("router-stress-test", function()
    tx.it("should handle adding 5,000 static routes efficiently", function()
        local handler = function() return "ok" end

        local t0 = os.clock()
        for i = 1, add_rules.max_routes do
            r:add("GET", "/path" .. i, { handler })
        end
        local t1 = os.clock()

        local res = r:search("GET", "/path5000")
        tx.equal(res.status, "found")

        local duration = t1 - t0
        if duration > add_rules.max_duration then
            tx.fail(duration .. "s" .. "/" .. add_rules.max_duration .. "s")
        else
            print(duration .. "s" .. "/" .. add_rules.max_duration .. "s")
        end
    end)

    tx.it("should handle 100,000 random lookups efficiently", function()
        local handler = function() return "ok" end

        -- preload 500 routes
        for i = 1, 500 do
            r:add("GET", "/lookup" .. i, { handler })
        end

        local t0 = os.clock()
        for i = 1, lookup_rules.max_routes do
            local idx = math.random(1, 500)
            local res = r:search("GET", "/lookup" .. idx)
            tx.equal(res.status, "found")
        end
        local t1 = os.clock()

        local duration = t1 - t0
        if duration > lookup_rules.max_duration then
            tx.fail(duration .. "s" .. "/" .. lookup_rules.max_duration .. "s")
        else
            print(duration .. "s" .. "/" .. lookup_rules.max_duration .. "s")
        end
    end)

    tx.it("should handle 100k dynamic lookups", function()
        local handler = function() return "ok" end
        r:add("GET", "/user/:id", { handler })

        local t0 = os.clock()
        for i = 1, dynamic_lookup_rules.max_routes do
            local res = r:search("GET", "/user/" .. i)
            tx.equal(res.status, "found")
            tx.equal(res.params.id, tostring(i))
        end
        local t1 = os.clock()

        local duration = t1 - t0
        if duration > dynamic_lookup_rules.max_duration then
            tx.fail(duration .. "s" .. "/" .. dynamic_lookup_rules.max_duration .. "s")
        else
            print(duration .. "s" .. "/" .. dynamic_lookup_rules.max_duration .. "s")
        end
    end)
end)
