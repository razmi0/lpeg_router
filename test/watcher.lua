#!/usr/bin/env luajit
--
--#region
local uv, inspect = require("luv"), require("inspect")

---@class WatcherConfig
---@field paths string[]|nil A list of directories to monitor for events such as change. Default to working directory.
---@field exec string The command to execute when a change is detected <runtime> <executed_file>.
---@field recursive boolean|nil Whether to monitor subdirectories recursively.
---@field ignore string[]|nil A list of files that can be ignored.
---@field verbose boolean|nil Clear or not the terminal before refreshing stuff.
---@field extra_args string[]|nil

local function log_error(field)
    error(field .. " not provided. Provide " .. field .. " = '<runtime> <executed_file>'")
end

local function log(str) print("\x1b[90m" .. str .. "\x1b[0m") end

local Watch = {}
Watch.__index = Watch

---@param config WatcherConfig
function Watch.new(config)
    if not config.exec then log_error("config.exec") end

    local parts = {}
    for token in config.exec:gmatch("%S+") do
        parts[#parts + 1] = token
    end

    local runtime       = parts[1]
    local executed_file = parts[2]
    local extra_args    = {}
    for i = 3, #parts do
        extra_args[#extra_args + 1] = parts[i]
    end

    if not runtime or not executed_file then log_error("config.exec") end
    return setmetatable({
        runtime = runtime,
        executed_file = executed_file,
        extra_args = extra_args,
        --
        events = {},
        paths = config.paths or { "./" },
        counter = 0,
        recursive = config and config.recursive or false,
        ignore_file_list = config and config.ignore or {},
        verbose = config and config.verbose or false
    }, Watch)
end

---@param event "change"|"error"|"start"|"rename"|"delete"|"create"
---@param cb function|nil
---@return self
function Watch:on(event, cb)
    if not event then return self end
    self.events[event] = function(err, filename)
        self:_spawn(err, filename, cb)
    end
    return self
end

function Watch:clear()
    if not self.verbose then
        log '\x1b[2J\x1b[H'
    end
end

function Watch:_spawn(err, filename, cb)
    assert(not err, "\x1b[31mUnexpected Error\x1b[0m \n" .. inspect(self))
    local handle

    local function kill()
        if handle then
            uv.process_kill(handle, "sigterm")
            uv.close(handle)
            handle = nil
        end
    end

    kill()
    self:clear()

    self.counter = self.counter + 1
    log(
        "(x" .. self.counter .. ") " ..
        os.date("%d/%m %H:%M")
    )

    local args = { self.executed_file }
    for _, a in ipairs(self.extra_args or {}) do
        table.insert(args, a)
    end

    handle = uv.spawn(self.runtime,
        {
            args = args,
            stdio = { 0, 1, 2 }, -- directly pipe child stds so no wrappers possible

        },
        function(code, signal) -- on exit
            if cb then cb(code) end
            if code == 0 then
                log("Process exited code " .. code)
            end
            kill()
        end
    )
end

function Watch:run()
    local timer_debouncer, timer_start = nil, uv.new_timer()
    local on_err                       = self.events["error"]
    local on_change                    = self.events["change"]
    local on_start                     = self.events["start"]
    local on_rename                    = self.events["rename"]
    local on_create                    = self.events["create"]
    local on_delete                    = self.events["delete"]

    local function debouncer(cb, delay)
        if timer_debouncer then uv.timer_stop(timer_debouncer) end
        timer_debouncer = uv.new_timer()
        uv.timer_start(timer_debouncer, delay, 0, function()
            uv.timer_stop(timer_debouncer)
            uv.close(timer_debouncer)
            timer_debouncer = nil
            cb()
        end)
    end

    -- stopping gracefully
    local signal = uv.new_signal()
    uv.signal_start(signal, "sigint", function(signame)
        self:clear()
        os.exit(1)
    end)

    -- watcher
    for i = 1, #self.paths, 1 do
        local path = self.paths[i]
        local ev = uv.new_fs_event()

        -- at start
        if on_start then
            uv.timer_start(timer_start, 0, 0, function()
                uv.timer_stop(timer_start)
                uv.close(timer_start)
                on_start(nil, path)
            end)
        end

        ev:start(path, { recursive = self.recursive },
            function(err, filename, events)
                for _, ignore_file in ipairs(self.ignore_file_list) do
                    if filename == ignore_file then
                        return
                    end
                end

                if err and on_err then
                    debouncer(function()
                        on_err(err, filename)
                    end, 50)
                    return
                end

                if events.change and on_change then
                    debouncer(function()
                        on_change(err, filename)
                    end, 50)
                end

                -- not recursive
                if events.rename then
                    if on_rename then
                        debouncer(function()
                            on_rename(nil, filename)
                        end, 50)
                    end

                    uv.fs_stat(filename, function(stat_err, stat_res)
                        if stat_err then
                            if on_delete then
                                debouncer(function()
                                    on_delete(nil, filename)
                                end, 50)
                            end
                        else
                            if on_create then
                                debouncer(function()
                                    on_create(nil, filename)
                                end, 50)
                            end
                        end
                    end)
                end
            end
        )
    end
    uv.run()
end

--#endregion

for i = 1, #arg, 1 do
    if arg[i]:match("--index") then
        Watch.new({
            paths = { "./" },
            recursive = true,
            exec = "luajit test/index.lua"
        }):on("change"):on("start")
            :run()
    elseif arg[i]:match("--bench") then
        Watch.new({
            paths = { "./" },
            recursive = true,
            exec = "luajit test/bench/stress.lua --add3 --lookup1 --dynamic_lookup1"
        }):on("change"):on("start")
            :run()
    else
        error("--index or --bench")
    end
end

return Watch
