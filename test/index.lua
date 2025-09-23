local router = require("lpeg-router") -- adjust path
local tx = require("test.tx")
tx.describe("router-test", function()
    tx.it("should register and match a static GET route", function()
        local r = router
        r:add({ "GET" }, { "/home" }, { function() return "ok" end })

        local res = r:search("GET", "/home")
        tx.equal(res.status, "found")
        tx.equal(#res.handlers, 1)
        tx.equal(res.params, nil)
    end)

    tx.it("should return not_found for unknown route", function()
        local r = router
        local res = r:search("GET", "/unknown")
        tx.equal(res.status, "not_found")
    end)

    tx.it("should return method_not_allowed if route exists but method does not", function()
        local r = router
        r:add({ "POST" }, { "/only-post" }, { function() return "ok" end })

        local res = r:search("GET", "/only-post")
        tx.equal(res.status, "method_not_allowed")
        tx.include(res.available_methods, "POST")
    end)

    tx.it("should handle dynamic parameter routes", function()
        local r = router
        r:add({ "GET" }, { "/user/:id" }, { function() return "ok" end })

        local res = r:search("GET", "/user/42")
        tx.equal(res.status, "found")
        tx.equal(res.params.id, "42")
    end)

    tx.it("should support multiple handlers", function()
        local r = router
        local h1, h2 = function() return "h1" end, function() return "h2" end
        r:add({ "GET" }, { "/multi" }, { h1, h2 })

        local res = r:search("GET", "/multi")
        tx.equal(#res.handlers, 2)
    end)

    tx.it("should inherit handlers from wildcard route", function()
        local r = router
        local mw = function() return "wild" end
        r:add({ "GET" }, { "/api/*" }, { mw })
        r:add({ "GET" }, { "/api/test" }, { function() return "test" end })

        local res = r:search("GET", "/api/test")
        tx.equal(res.status, "found")
        tx.include(res.handlers[1](), "test")
        tx.include(res.handlers[2](), "wild")
    end)

    tx.it("should normalize paths without leading slash", function()
        local r = router
        r:add({ "GET" }, { "about" }, { function() return "ok" end })

        local res = r:search("GET", "/about")
        tx.equal(res.status, "found")
    end)

    tx.it("should allow trailing slashes", function()
        local r = router
        r:add({ "GET" }, { "/docs" }, { function() return "ok" end })

        local res = r:search("GET", "/docs/")
        tx.equal(res.status, "found")
    end)

    tx.it("should update handlers if path already registered", function()
        local r = router
        r:add({ "GET" }, { "/dup" }, { function() return "old" end })
        r:add({ "GET" }, { "/dup" }, { function() return "new" end })

        local res = r:search("GET", "/dup")
        tx.equal(res.status, "found")
        tx.equal(res.handlers[1](), "new")
    end)
end)
