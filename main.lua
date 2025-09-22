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
local GRAMMAR = P {
    "ROUTE",
    ROUTE    = Ct((P("/") * V("SEGMENT")) ^ 1),
    STATIC   = C((1 - S("/:")) ^ 1),
    PARAM    = P(DYNAMIC_IDENTIFIER) * C((1 - P("/")) ^ 1),
    WILDCARD = P("*"),
    SEGMENT  =
        (
            V("WILDCARD") / function()
                return {
                    wildcard = true,
                    pattern = P("/") * C(P(1) ^ 0) / function(value)
                        return { wildcard = value }
                    end
                }
            end
        )
        +
        (
            V("STATIC") / function(part)
                return {
                    static = part,
                    pattern = P("/") * C(P(part)) / function(a) return { static = a } end
                }
            end
        )
        +
        (
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
        )




}

local update_route_data = function(router, route, methods, handlers)
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
    local wilds = {}
    for _, node in ipairs(captures) do
        if node.param then
            params[node.param.name] = node.param.value
        elseif node.wildcard then
            for match in (node.wildcard .. "/"):gmatch("(.-)" .. "/") do
                wilds[#wilds + 1] = match
            end
            params["wildcard"] = wilds
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

local create_node = function(methods, handlers)
    local new_node = {}
    for _, method in ipairs(methods) do
        new_node[method] = {}
        for _, cb in ipairs(handlers) do
            new_node[method][#new_node[method] + 1] = cb
        end
    end
    return new_node
end

local prefix_slash = function(str)
    if str:match("^[^/]") then return "/" .. str end
    return str
end

local router = setmetatable({
    _compiled_strand = nil,
    _route_data = {},  -- ( [id] : { [method] : handlers } )[]
    _route_cache = {}, -- ( [path] : id )[]
    size = 0,
    add = function(self, methods, route, handlers)
        route = prefix_slash(route)
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

        -- segment identification
        local parsed = assert(
            lpeg.match(GRAMMAR, route),
            "\n\27[38;5;196m[Error] Parsing failed\27[0m : " .. route
        )

        -- print(inspect(parsed))

        -- lpeg strand update
        -- if there's wildcards, store thing to attach to route_id ?
        local strand = nil
        for _, entry in ipairs(parsed) do
            --                   ...    * P("/") * C((1 - P("/")) ^ 1) ..
            strand = strand and (strand * entry.pattern) or entry.pattern
        end

        local route_pattern = (strand * (P("/") ^ 0) * -P(1)) / function(...)
            local caps = { ... }
            return { route_id = route_id, captures = caps }
        end

        self._compiled_strand = --  ...    * P("/") * C((1 - P("/")) ^ 1) ..
            self._compiled_strand and (route_pattern + self._compiled_strand)
            or route_pattern
    end,
    search = function(self, method, req_route)
        req_route = prefix_slash(req_route)
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
    end,
}, {})

return router
