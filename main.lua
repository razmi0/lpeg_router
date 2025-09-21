-- [x] static
-- [x] dynamic param
-- [ ] dynamic param with pattern
-- [ ] dynamic param with default value ?
-- [ ] dynamic wildcards

local inspect = require("inspect")
local lpeg = require("lpeg")
local P, C, V, Ct, S = lpeg.P, lpeg.C, lpeg.V, lpeg.Ct, lpeg.S
--
local DYNAMIC_IDENTIFIER = ":"
--


local function update_strand(router, parsed, id)
    local strand = nil
    for _, entry in ipairs(parsed) do
        strand = strand and (strand * entry.pattern) or entry.pattern
    end

    local route_pattern = strand / function(...)
        local caps = { ... }
        return { route_id = id, captures = caps }
    end

    router._compiled_strand =
        router._compiled_strand and (router._compiled_strand + route_pattern)
        or route_pattern
end

local function update_route_data(router, route, methods, handlers)
    if router._route_cache[route] then
        local cache_id = router._route_cache[route]
        local stored_data = router._route_data[cache_id]
        for _, m in ipairs(methods) do
            if not stored_data[m] then
                stored_data[m] = {}
            end
            for _, cb in ipairs(handlers) do
                table.insert(stored_data[m], 1, cb)
            end
        end
        return cache_id
    end
end

local create_id = function(router)
    router.size = router.size + 1
    return "_" .. router.size
end

local get_params = function(captures)
    local params = {}
    for _, node in ipairs(captures) do
        if node.param then
            params[node.param.name] = node.param.value
        end
    end
    return params
end

local get_methods = function(route_data)
    local available_methods = {}
    for m, _ in pairs(route_data) do
        available_methods[#available_methods + 1] = m
    end
    return available_methods
end

local function create_node(methods, handlers)
    local new_node = {}
    for _, method in ipairs(methods) do
        new_node[method] = {}
        for _, cb in ipairs(handlers) do
            new_node[method][#new_node[method] + 1] = cb
        end
    end
    return new_node
end

local router = setmetatable({
    _compiled_strand = nil,
    _route_data = {},
    _route_cache = {},
    size = 0,
    _grammar = P {
        "ROUTE",
        ROUTE   = Ct((P("/") * V("SEGMENT")) ^ 1),
        STATIC  = C((1 - S("/:")) ^ 1),
        PARAM   = P(DYNAMIC_IDENTIFIER) * C((1 - P("/")) ^ 1),
        SEGMENT =
            (
                V("STATIC") / function(part)
                    return {
                        static = part,
                        pattern = P("/") * C(P(part)) / function(a) return { static = a } end
                    }
                end
            )
            + (
                V("PARAM") / function(name)
                    return {
                        param = name,
                        pattern = P("/") * C((1 - P("/")) ^ 1) / function(value)
                            return {
                                param = { name = name, value = value }
                            }
                        end
                    }
                end
            ),
    },
    add = function(self, methods, route, handlers)
        if type(methods) == "string" then methods = { methods } end
        if type(handlers) == "function" then handlers = { handlers } end

        -- if route is already stored => update_route_data
        -- _route_data is updated at given route_id and strand is not updated
        local is_updated = update_route_data(self, route, methods, handlers)
        if is_updated then return end

        -- route is processed
        local route_id = create_id(self)
        self._route_cache[route] = route_id
        self._route_data[route_id] = create_node(methods, handlers)

        local parsed = assert(
            lpeg.match(self._grammar, route),
            "\n\27[38;5;196m[Error] Parsing failed\27[0m : " .. route
        )

        update_strand(self, parsed, route_id)
    end,
    search = function(self, method, req_route)
        local route = lpeg.match(self._compiled_strand, req_route)
        if not route then return { status = "not_found" } end
        --
        local route_data = self._route_data[route.route_id]
        local handlers = route_data[method]
        --
        if not handlers then
            return {
                status = "method_not_allowed",
                available_methods = get_methods(route_data)
            }
        end
        --
        local params = get_params(route.captures)
        return {
            status = "found",
            handlers = handlers,
            params = params
        }
    end
}, {})

local cbs = { function()

end, function()

end }

router:add({ "GET", "POST" }, "/products/:type/:id", cbs)
router:add({ "POST" }, "/products/:type/:id", cbs)
router:add({ "PUT" }, "/products/:type/:id", cbs)
local data_1 = router:search("PUT", "/products/shorts/42")
-- router:add({ "GET", "POST" }, "/users/:id", cbs)

print(inspect(data_1))


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
