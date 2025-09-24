local r = require("lpeg-router").new()
local tx = require("test.lib.tx")
--
local COMMON_METHODS = { "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" }

tx.beforeEach = function()
    r = require("lpeg-router").new()
end

tx.describe("router-test", function()
    tx.it("should register and match a static GET route", function()
        r:add({ "GET" }, { "/home" }, { function() return "ok" end })

        local res = r:search("GET", "/home")
        tx.equal(res.status, "found")
        tx.equal(#res.handlers, 1)
        tx.equal(res.params, nil)
    end)

    tx.it("should return not_found for unknown route", function()
        local res = r:search("GET", "/unknown")
        tx.equal(res.status, "not_found")
    end)

    tx.it("should return method_not_allowed if route exists but method does not", function()
        r:add({ "POST" }, { "/only-post" }, { function() return "ok" end })

        local res = r:search("GET", "/only-post")
        tx.equal(res.status, "method_not_allowed")
        tx.include(res.available_methods, "POST")
    end)

    tx.it("should handle dynamic parameter routes", function()
        r:add({ "GET" }, { "/user/:id" }, { function() return "ok" end })

        local res = r:search("GET", "/user/42")
        tx.equal(res.status, "found")
        tx.equal(res.params.id, "42")
    end)

    tx.it("should support multiple handlers", function()
        local h1, h2 = function() return "h1" end, function() return "h2" end
        r:add({ "GET" }, { "/multi" }, { h1, h2 })

        local res = r:search("GET", "/multi")
        tx.equal(#res.handlers, 2)
    end)

    tx.it("should inherit handlers from wildcard route", function()
        local mw = function() return "wild" end
        r:add({ "GET" }, { "/api/*" }, { mw })
        r:add({ "GET" }, { "/api/test" }, { function() return "test" end })

        local res = r:search("GET", "/api/test")
        tx.equal(res.status, "found")
        tx.include(res.handlers[1](), "wild")
        tx.include(res.handlers[2](), "test")
    end)

    tx.it("should normalize paths without leading slash", function()
        r:add({ "GET" }, { "about" }, { function() return "ok" end })

        local res = r:search("GET", "/about")
        tx.equal(res.status, "found")
    end)

    tx.it("should allow trailing slashes", function()
        r:add({ "GET" }, { "/docs" }, { function() return "ok" end })

        local res = r:search("GET", "/docs/")
        tx.equal(res.status, "found")
    end)

    tx.it("should not update if path already registered at given method", function()
        r:add({ "GET" }, { "/dup" }, { function() return "first" end })
        r:add({ "GET" }, { "/dup" }, { function() return "second" end })

        local res = r:search("GET", "/dup")
        tx.equal(res.status, "found")
        tx.equal(#res.handlers, 1)
        tx.equal(res.handlers[1](), "first")
    end)

    tx.it("should update if path already registered at different method", function()
        r:add({ "GET" }, { "/pud" }, { function() return "first" end })
        r:add({ "POST" }, { "/pud" }, { function() return "second" end })

        local res = r:search("POST", "/pud")
        tx.equal(res.status, "found")
        tx.equal(#res.handlers, 1)
        tx.equal(res.handlers[1](), "second")
    end)

    tx.it("should expand methods == nil into common methods", function()
        r:add(nil, { "/expand" }, { function() return "ok" end })

        for _, m in ipairs(COMMON_METHODS) do
            local res = r:search(m, "/expand")
            tx.equal(res.status, "found")
        end
    end)

    tx.it("should expand methods == '*' into common methods", function()
        r:add("*", { "/expand2" }, { function() return "ok" end })

        for _, m in ipairs(COMMON_METHODS) do
            local res = r:search(m, "/expand2")
            tx.equal(res.status, "found")
        end
    end)

    tx.it("should throw if paths == nil", function()
        tx.throws(function()
            r:add({ "GET" }, nil, { function() end })
        end)
    end)

    tx.it("should throw if handlers == nil", function()
        tx.throws(function()
            r:add({ "GET" }, { "/nohandler" }, nil)
        end)
    end)

    tx.it("should accept parameters as his primary type not just table", function()
        r:add("GET", "/single-method", function() return "ok" end)
        local res = r:search("GET", "/single-method")
        tx.equal(res.status, "found")
        tx.equal(res.handlers[1](), "ok")
    end)

    tx.it("should allow multiple middlewares stacking", function()
        local mw1 = function() return "mw1" end
        local mw2 = function() return "mw2" end
        local leaf = function() return "leaf" end

        r:add({ "GET" }, { "*" }, { mw1 })
        r:add({ "GET" }, { "/api/*" }, { mw2 })
        r:add({ "GET" }, { "/api/data" }, { leaf })

        local res = r:search("GET", "/api/data")
        tx.equal(res.status, "found")
        tx.equal(#res.handlers, 3)
        tx.equal(res.handlers[1](), "mw1")
        tx.equal(res.handlers[2](), "mw2")
        tx.equal(res.handlers[3](), "leaf")
    end)
end)
