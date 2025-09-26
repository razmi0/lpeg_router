-- [x] static
-- [x] dynamic param
-- [ ] dynamic param with pattern
-- [ ] dynamic param with optionnal
-- [ ] dynamic param with default value ?
-- [x] dynamic wildcards
-- [x] method agnostic

local inspect            = require("inspect")
local lpeg               = require("lpeg")
local P, C, V, Ct, S, Cs = lpeg.P, lpeg.C, lpeg.V, lpeg.Ct, lpeg.S, lpeg.Cs
--
local Router             = {}
Router.__index           = Router

local
DYNAMIC_IDENTIFIER,
WILDCARD_IDENTIFIER,
ALL_METHOD_IDENTIFIER,
SEPARATOR,
OPTIONAL_IDENTIFIER,
OPEN_VALIDATION,
CLOSE_VALIDATION
                         = ":", "*", "__all", "/", "?", "(", ")"
function Router.new()
    return setmetatable({
        DYNAMIC_IDENTIFIER = DYNAMIC_IDENTIFIER,
        WILDCARD_IDENTIFIER = WILDCARD_IDENTIFIER,
        ALL_METHOD_IDENTIFIER = ALL_METHOD_IDENTIFIER,
        SEPARATOR = SEPARATOR,
        OPTIONAL_IDENTIFIER = OPTIONAL_IDENTIFIER,
        OPEN_VALIDATION = OPEN_VALIDATION,
        CLOSE_VALIDATION = CLOSE_VALIDATION,
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
        routes = {}, -- ( [path] : { [method] : handlers } )[]
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
        _wilds_patterns = {},
        ---@private
        _grammar = P {
            "ROUTE",
            SEPARATOR = P(SEPARATOR),
            STATIC    = C((1 - S(
                SEPARATOR ..
                WILDCARD_IDENTIFIER ..
                DYNAMIC_IDENTIFIER ..
                OPTIONAL_IDENTIFIER ..
                OPEN_VALIDATION ..
                CLOSE_VALIDATION
            )) ^ 1),
            PARAM     = P(":") * C((1 - S("/:?(")) ^ 1) * C(P("?") ^ -1) * Cs((P("(") * C((1 - S(")")) ^ 0) * P(")")) ^ -1),
            WILDCARD  = P(WILDCARD_IDENTIFIER),
            ROUTE     = Ct((P(SEPARATOR) * V("SEGMENT")) ^ 1),
            SEGMENT   =
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
                    V("PARAM") / function(name, opt, validation)
                        local val = validation ~= "" and validation:sub(2, -2) or nil
                        return {
                            param = name,
                            optional = opt ~= "" or nil,
                            validation = val,
                            pattern = P(SEPARATOR) * C((1 - P(SEPARATOR)) ^ 1) / function(value)
                                if (val and value) and not value:match(val) then
                                    return "failed_validation"
                                end
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

    if self.routes[path] then
        -- local cache_id = self._route_cache[path]
        local stored_data = self.routes[path]
        -- if [method,path] is already stored => no updating
        if not stored_data[method] then
            stored_data[method] = { handlers = {}, inherit = {} }
            for _, cb in ipairs(handlers) do
                table.insert(stored_data[method].handlers, cb)
            end
        end
        return
    end

    -- storing associated path data : Route
    local route = self._create_route(method, handlers)
    self.routes[path] = route

    -- segments identifications
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

    local route_pattern = assert(
        self:_compile(strand * (P(self.SEPARATOR) ^ 0) * -P(1) / function(...) -- strand * separator * end of path
            local caps = { ... }
            if caps[1] == "failed_validation" then return { path = path } end
            return { captures = caps, path = path }
        end),
        "\n\27[38;5;196m[Error] Compiling failed\27[0m : " .. path
    )

    local collected_groups = {}
    for _, pattern in ipairs(self._wilds_patterns) do
        local parsed_wild = lpeg.match(pattern, path)
        if parsed_wild then
            local wild_data = self.routes[parsed_wild.path]
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

function Router:search(method, path)
    path = self._format_path(path)
    local create_result = function(status, available_methods, handlers, params)
        return {
            status = status,
            available_methods = available_methods,
            handlers = handlers,
            params = params,
            meta = {
                method = method,
                path = path
            }
        }
    end

    if not self._compiled_strand then
        return create_result("not_found")
    end

    local route = lpeg.match(self._compiled_strand, path)
    if not route or not route.captures then
        return create_result("not_found")
    end

    local route_data = self.routes[route.path][method]
        or self.routes[route.path][self.ALL_METHOD_IDENTIFIER]

    if not route_data then
        local available = {}
        for m, _ in pairs(self.routes[route.path]) do
            table.insert(available, m)
        end
        return create_result("method_not_allowed", available)
    end

    local handlers = {}
    for _, h in ipairs(route_data.handlers or {}) do
        handlers[#handlers + 1] = h
    end
    for _, h in ipairs(route_data.inherit or {}) do
        table.insert(handlers, 1, h)
    end

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

    return create_result("found", nil, handlers, next(params) and params or nil)
end

return Router
