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
local SYMBOLS            = {
    DYNAMIC  = ":",
    WILDCARD = "*",
    ALL      = "__all",
    SEP      = "/",
    OPTIONAL = "?",
    OPEN     = "(",
    CLOSE    = ")",
}
local NOT_IN_STATIC      = table.concat({
    SYMBOLS.SEP,
    SYMBOLS.WILDCARD,
    SYMBOLS.DYNAMIC,
    SYMBOLS.OPTIONAL,
    SYMBOLS.OPEN,
    SYMBOLS.CLOSE,
})

local function _compile(self, route_pattern)
    self._compiled_strand =                                               --  ...     P("/") * C((1 - P("/")) ^ 1) * (P("/") ^ 0) * -P(1)
        self._compiled_strand and (route_pattern + self._compiled_strand) -- lpeg ordered choice
        or route_pattern
    return route_pattern
end

local function _create_route(method, handlers)
    return {
        [method or SYMBOLS.ALL] = {
            handlers = { unpack(handlers) },
            inherit = {}
        }
    }
end

local function _format_path(path)
    if path:match("^[^" .. SYMBOLS.SEP .. "]") then
        return SYMBOLS.SEP .. path
    end
    return path
end

local Router   = {}
Router.__index = Router
function Router.new()
    return setmetatable({
        ---@private
        _compiled_strand = nil,
        ---@private
        _compile = _compile,
        ---@private
        routes = {}, -- ( [path] : { [method] : handlers } )[]
        ---@private
        _create_route = _create_route,
        ---@private
        _format_path = _format_path,
        ---@private
        _wilds_patterns = {},
        ---@private
        _grammar = P {
            "ROUTE",
            PARAM     =
                P(SYMBOLS.DYNAMIC)
                * C((1 - S(NOT_IN_STATIC)) ^ 1)
                * C(P(SYMBOLS.OPTIONAL) ^ -1)
                * Cs((P(SYMBOLS.OPEN) * C((1 - S(SYMBOLS.CLOSE)) ^ 0) * P(SYMBOLS.CLOSE)) ^ -1),
            SEPARATOR = P(SYMBOLS.SEP),
            STATIC    = C((1 - S(NOT_IN_STATIC)) ^ 1),
            WILDCARD  = P(SYMBOLS.WILDCARD),
            ROUTE     = Ct((P(SYMBOLS.SEP) * V("SEGMENT")) ^ 1),
            SEGMENT   =
                (
                    V("STATIC") / function(part)
                        return {
                            static = part,
                            pattern = P(SYMBOLS.SEP) * C(P(part)) / function(a) return { static = a } end
                        }
                    end

                )
                +
                (
                    V("WILDCARD") / function()
                        return {
                            wildcard = true,
                            pattern = P(SYMBOLS.SEP) * C(P(1) ^ 0) / function(value)
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
                            pattern = P(SYMBOLS.SEP) * C((1 - P(SYMBOLS.SEP)) ^ 1) / function(value)
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
        self:_compile(strand * (P(SYMBOLS.SEP) ^ 0) * -P(1) / function(...) -- strand * separator * end of path
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
            local src = wild_data[method] or wild_data[SYMBOLS.ALL]
            if src and src.handlers then
                table.insert(collected_groups, 1, src.handlers)
            end
        end
    end

    if #collected_groups > 0 then
        local dst = route[method] or route[SYMBOLS.ALL]
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
        or self.routes[route.path][SYMBOLS.ALL]

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
            for match in (node.wildcard .. SYMBOLS.SEP):gmatch("(.-)" .. SYMBOLS.SEP) do
                wilds[#wilds + 1] = match
            end
            params["*"] = wilds
        end
    end

    return create_result("found", nil, handlers, next(params) and params or nil)
end

return Router
