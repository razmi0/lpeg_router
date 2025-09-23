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
            if stored_data[m] then
                stored_data[m].handlers = {}
                for _, cb in ipairs(handlers) do
                    table.insert(stored_data[m].handlers, cb)
                end
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
            params["*"] = wilds
        end
    end
    return next(params) and params or nil
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
        new_node[method] = {
            handlers = {}, inherit = {}
        }
        for _, cb in ipairs(handlers) do
            new_node[method].handlers[#new_node[method].handlers + 1] = cb
        end
    end
    return new_node
end

local prefix_slash = function(str)
    if str:match("^[^/]") then return "/" .. str end
    return str
end

local default = function(methods, paths, handlers)
    local common_methods = { "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" }

    if type(paths) == "string" then
        paths = { paths }
    elseif not paths then
        error("router : paths must be a string or a table of strings")
    end

    if type(handlers) == "function" then
        handlers = { handlers }
    elseif not handlers then
        handlers = {}
    end

    if type(methods) == "string" then
        methods = { methods }
    elseif not methods then
        methods = common_methods
    end
    return methods, paths, handlers
end

local router = setmetatable({
    size = 0,
    ---@private
    _compiled_strand = nil,
    ---@private
    _route_data = {},  -- ( [id] : { [method] : handlers } )[]
    ---@private
    _route_cache = {}, -- ( [path] : id )[]
    ---@private
    _wilds_patterns = {},
    add = function(self, methods, paths, handlers)
        methods, paths, handlers = default(methods, paths, handlers)

        for _, path in ipairs(paths) do
            path = prefix_slash(path)
            -- if path is already stored => update_route_data
            -- _route_data is updated at given route_id and strand is not updated
            local is_updated = update_route_data(self, path, methods, handlers)
            if is_updated then return end

            -- path is processed
            local route_id = create_id(self)
            self._route_cache[path] = route_id

            -- segment of the path identification
            local parts = assert(
                lpeg.match(GRAMMAR, path),
                "\n\27[38;5;196m[Error] Parsing failed\27[0m : " .. path
            )

            -- lpeg strand update
            local strand = nil
            for _, entry in ipairs(parts) do
                --                   ...    * P("/") * C((1 - P("/")) ^ 1) ..
                local p = entry.pattern
                strand = strand and (strand * p) or p -- lpeg concatenation
            end

            local route_pattern = (strand * (P("/") ^ 0) * -P(1)) / function(...)
                local caps = { ... }
                return { route_id = route_id, captures = caps }
            end

            -- storing path data node
            local route_node = create_node(methods, handlers)
            self._route_data[route_id] = route_node

            -- inherited routes are the wild ones already registered
            for _, pattern in ipairs(self._wilds_patterns) do
                local parsed_wild = lpeg.match(pattern, path) -- we test wild path against current route
                if parsed_wild then                           -- if match, add wilds handlers to route inherited array of handlers respecting methods
                    local wild_data = self._route_data[parsed_wild.route_id]
                    for _, m in ipairs(methods) do
                        local src = wild_data[m]
                        local dst = route_node[m]
                        if src and dst then
                            for _, h in ipairs(src.handlers) do
                                dst.inherit[#dst.inherit + 1] = h
                            end
                        end
                    end
                end
            end

            -- store wild one
            if parts[#parts].wildcard then
                self._wilds_patterns[#self._wilds_patterns + 1] = route_pattern
            end

            self._compiled_strand =                                               --  ...     P("/") * C((1 - P("/")) ^ 1) * (P("/") ^ 0) * -P(1)
                self._compiled_strand and (route_pattern + self._compiled_strand) -- lpeg ordered choice
                or route_pattern
        end
    end,
    --
    search = function(self, method, req_route)
        req_route = prefix_slash(req_route)
        local route = lpeg.match(self._compiled_strand, req_route)
        if not route then
            return {
                status = "not_found"
            }
        end
        --
        local route_data = self._route_data[route.route_id]
        if not route_data[method] then
            return {
                status = "method_not_allowed",
                available_methods = get_methods(route_data)
            }
        end
        for _, h in ipairs(route_data[method].inherit) do
            route_data[method].handlers[#route_data[method].handlers + 1] = h
        end
        local handlers = route_data[method].handlers
        --
        local params = get_params(route.captures)
        return {
            status = "found",
            handlers = handlers,
            params = params,
            meta = {
                method = method,
                path = req_route
            }
        }
    end,
}, {})

return router
