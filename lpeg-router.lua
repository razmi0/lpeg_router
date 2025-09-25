-- [x] static
-- [x] dynamic param
-- [ ] dynamic param with pattern
-- [ ] dynamic param with optionnal
-- [ ] dynamic param with default value ?
-- [x] dynamic wildcards
-- [x] method agnostic

local inspect = require("inspect")
local lpeg = require("lpeg")
local P, C, V, Ct, S = lpeg.P, lpeg.C, lpeg.V, lpeg.Ct, lpeg.S
--
local Router = {}
Router.__index = Router

function Router.new(
    DYNAMIC_IDENTIFIER,
    WILDCARD_IDENTIFIER,
    ALL_METHOD_IDENTIFIER,
    SEPARATOR
)
    DYNAMIC_IDENTIFIER = DYNAMIC_IDENTIFIER or ":"
    WILDCARD_IDENTIFIER = WILDCARD_IDENTIFIER or "*"
    ALL_METHOD_IDENTIFIER = ALL_METHOD_IDENTIFIER or "__all"
    SEPARATOR = SEPARATOR or "/"
    return setmetatable({
        DYNAMIC_IDENTIFIER = DYNAMIC_IDENTIFIER,
        WILDCARD_IDENTIFIER = WILDCARD_IDENTIFIER,
        ALL_METHOD_IDENTIFIER = ALL_METHOD_IDENTIFIER,
        SEPARATOR = SEPARATOR,
        size = 0,
        ---@private
        _create_id = function(self)
            self.size = self.size + 1
            return "_" .. self.size
        end,
        ---@private
        _compiled_strand = nil,
        ---@private
        _compile = function(self, route_pattern)
            self._compiled_strand =                                               --  ...     P("/") * C((1 - P("/")) ^ 1) * (P("/") ^ 0) * -P(1)
                self._compiled_strand and (route_pattern + self._compiled_strand) -- lpeg ordered choice
                or route_pattern
            return route_pattern
        end,
        ---@private
        routes = {}, -- ( [id] : { [method] : handlers } )[]
        ---@private
        _create_route = function(method, handlers)
            local route = {}
            if not method then
                route[ALL_METHOD_IDENTIFIER] = { handlers = { unpack(handlers) }, inherit = {} }
                return route
            end
            route[method] = { handlers = { unpack(handlers) }, inherit = {} }
            return route
        end,
        ---@private
        _format_path = function(path)
            if path:match("^[^" .. SEPARATOR .. "]") then return SEPARATOR .. path end
            return path
        end,
        ---@private
        _route_cache = {}, -- ( [path] : id )[]
        ---@private
        _wilds_patterns = {},
        ---@private
        _grammar = P {
            "ROUTE",
            SEPARATOR = P(SEPARATOR),
            STATIC    = C((1 - S(SEPARATOR .. WILDCARD_IDENTIFIER .. DYNAMIC_IDENTIFIER)) ^ 1),
            PARAM     = P(DYNAMIC_IDENTIFIER) * C((1 - P(SEPARATOR)) ^ 1),
            WILDCARD  = P(WILDCARD_IDENTIFIER),
            ROUTE     = Ct((P(SEPARATOR) * V("SEGMENT")) ^ 1),
            SEGMENT   =
                (
                    V("WILDCARD") / function()
                        return {
                            wildcard = true,
                            pattern = P(SEPARATOR) * C(P(1) ^ 0) / function(value)
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
                            pattern = P(SEPARATOR) * C(P(part)) / function(a) return { static = a } end
                        }
                    end
                )
                +
                (
                    V("PARAM") / function(name)
                        return {
                            param = name,
                            pattern = P(SEPARATOR) * C((1 - P(SEPARATOR)) ^ 1) / function(value)
                                return {
                                    param = { name = name, value = value }
                                }
                            end
                        }
                    end
                )
        }
    }, Router)
end

function Router:add(method, path, handlers)
    if type(handlers) == "function" then
        handlers = { handlers }
    end

    path = self._format_path(path)

    if self._route_cache[path] then
        local cache_id = self._route_cache[path]
        local stored_data = self.routes[cache_id]
        -- if [method,path] is already stored => no updating
        if not stored_data[method] then
            stored_data[method] = { handlers = {}, inherit = {} }
            for _, cb in ipairs(handlers) do
                table.insert(stored_data[method].handlers, cb)
            end
        end
        return
    end

    -- path is processed
    local route_id = self:_create_id()
    self._route_cache[path] = route_id

    -- storing path data node
    local route = self._create_route(method, handlers)
    self.routes[route_id] = route

    -- segment of the path identification
    local parts = assert(
        lpeg.match(self._grammar, path),
        "\n\27[38;5;196m[Error] Parsing failed\27[0m : " .. path
    )

    -- lpeg strand
    local strand = nil
    for _, entry in ipairs(parts) do
        local p = entry.pattern               -- ...    * P("/") * C((1 - P("/")) ^ 1) ..
        strand = strand and (strand * p) or p -- lpeg concatenation
    end

    local on_strand = function(...)
        local caps = { ... }
        return { route_id = route_id, captures = caps }
    end

    local route_pattern = assert(
        self:_compile((strand * (P(self.SEPARATOR) ^ 0) * -P(1)) / on_strand),
        "\n\27[38;5;196m[Error] Compiling failed\27[0m : " .. path
    )

    local collected_groups = {}
    for _, pattern in ipairs(self._wilds_patterns) do
        local parsed_wild = lpeg.match(pattern, path)
        if parsed_wild then
            local wild_data = self.routes[parsed_wild.route_id]
            local src = wild_data[method] or wild_data[self.ALL_METHOD_IDENTIFIER]
            if src and src.handlers then
                table.insert(collected_groups, 1, src.handlers)
            end
        end
    end

    if #collected_groups > 0 then
        local dst = route[method] or route[self.ALL_METHOD_IDENTIFIER]
        if dst then
            local final_inherit = {}
            for _, group in ipairs(collected_groups) do
                for _, handler in ipairs(group) do
                    table.insert(final_inherit, handler)
                end
            end
            dst.inherit = final_inherit
        end
    end

    -- store wild one ( wild segment is always the last one )
    if parts[#parts].wildcard then
        self._wilds_patterns[#self._wilds_patterns + 1] = route_pattern
    end
end

function Router:search(method, req_path)
    req_path = self._format_path(req_path)
    if not self._compiled_strand then
        return { status = "not_found" }
    end
    local route = lpeg.match(self._compiled_strand, req_path)
    if not route then
        return { status = "not_found" }
    end
    --
    local route_data = self.routes[route.route_id][method] or self.routes[route.route_id][self.ALL_METHOD_IDENTIFIER]
    if not route_data then
        local available = {}
        for m, _ in pairs(self.routes[route.route_id]) do
            table.insert(available, m)
        end
        return {
            status = "method_not_allowed",
            available_methods = available
        }
    end
    for _, h in ipairs(route_data.inherit) do
        table.insert(route_data.handlers, 1, h)
    end
    local handlers = route_data.handlers
    --

    local params = {}
    local wilds = {}
    for _, node in ipairs(route.captures) do
        if node.param then
            params[node.param.name] = node.param.value
        elseif node.wildcard then
            for match in (node.wildcard .. self.SEPARATOR):gmatch("(.-)" .. self.SEPARATOR) do
                wilds[#wilds + 1] = match
            end
            params["*"] = wilds
        end
    end

    return {
        status = "found",
        handlers = handlers,
        params = next(params) and params or nil,
        meta = {
            method = method,
            path = req_path
        }
    }
end

return Router
