local inspect = require("inspect")
local router = require("main")
local cbs = {
    function() print("1") end,
}

router:add(nil, "*", cbs)
router:add(nil, "nil", nil)
-- local data_1 = assert(router:search("GET", "/items/item/ouch/lol"))
local data_2 = assert(router:search("PATCH", "/items"))
-- print("data_1", inspect(data_1))
print("data_2", inspect(data_2))
-- router:add({ "GET", "POST" }, "/users/:id", cbs)

-- print(inspect(data_1))


-- router:add("POST", "/users/:id", function()
--     print("POST")
-- end)


-- router:add("GET", "/users/:id", function()
--     print("GET")
-- end)

-- routes:add("POST", "/users/:id", { function()
--     print("POST")
-- end, function()
--     print("POST")
-- end })

--
-- local data_2 = router:search("POST", "/users/42")
-- print(inspect(data_1))
-- print(inspect(data_2))
