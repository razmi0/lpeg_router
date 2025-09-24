local inspect = require("inspect")
local Tx = {}

-- Helpers

local function red(str)
    return "\27[31m" .. str .. "\27[0m"
end

local function green(str)
    return "\27[32m" .. str .. "\27[0m"
end

local function lgrey(str)
    return "\27[90m" .. str .. "\27[0m"
end

local function deep_contains(container, value)
    if type(container) == "string" then
        return container:find(value, 1, true) ~= nil
    elseif type(container) == "table" then
        for _, v in pairs(container) do
            if v == value then
                return true
            end
            if type(v) == "table" and deep_contains(v, value) then
                return true
            end
        end
    end
    return false
end

-- Printing Queue

local queue = {
    name      = "",
    output    = {
        pluses = "",
        rules = ""
    },
    testCount = 0,
    failCount = 0,
}

local function addPlus(plus)
    queue.output.pluses = queue.output.pluses .. plus
end

local function addRule(msg, err)
    queue.output.rules = queue.output.rules .. red("   " .. msg .. "\n" .. "    " .. err .. "\n")
end

local function addOutput(msg, err)
    local success = not msg and not err
    if success then
        addPlus(green("+"))
    else
        addPlus(red("+"))
        addRule(msg, err)
    end
end

local function addCount()
    queue.testCount = queue.testCount + 1
end

local function addFailed()
    queue.failCount = queue.failCount + 1
end

local function addName(_name)
    queue.name = _name
end

local function printResults(mute)
    local successes = queue.testCount - queue.failCount
    local output = function()
        print("[Tx] " .. queue.name)
        print(lgrey(tostring(successes .. "/" .. queue.testCount)) .. " " .. queue.output.pluses)
        if queue.output.rules ~= "" then
            print(queue.output.rules)
        end
    end
    if mute then
        if queue.failCount > 0 then
            output()
        end
        return
    end
    output()
end

-- Lib

function Tx.describe(xname, fn, mute)
    mute = mute or Tx.mute or false
    queue = {
        name      = "",
        output    = {
            pluses = "",
            rules = ""
        },
        testCount = 0,
        failCount = 0,
    }
    addName(xname)
    fn()
    printResults(mute)
    return queue
end

function Tx.it(msg, func)
    if Tx.beforeEach then
        Tx.beforeEach()
    end
    addCount()
    local success, internal_err_msg = pcall(func)
    if not success then
        addFailed()
        addOutput(msg, internal_err_msg)
    else
        addOutput()
    end
    if Tx.afterEach then
        Tx.afterEach()
    end
end

function Tx.equal(actual, expected)
    local function deep_equal(a, b)
        if type(a) ~= type(b) then
            return false
        end
        if type(a) ~= "table" then
            return a == b
        end

        local checked_keys = {}

        for k, v in pairs(a) do
            if not deep_equal(v, b[k]) then
                return false
            end
            checked_keys[k] = true
        end

        for k in pairs(b) do
            if not checked_keys[k] then
                return false
            end
        end

        return true
    end

    if not deep_equal(actual, expected) then
        error(red(inspect(actual) .. " ~= " .. inspect(expected)))
    end
end

function Tx.include(container, value)
    if not deep_contains(container, value) then
        error(red("Did not expect to find " .. tostring(value)))
    end
end

function Tx.not_include(container, value)
    if deep_contains(container, value) then
        error(red("Did not expect to find " .. tostring(value)))
    end
end

function Tx.contain(string_val, substring)
    if not string.find(string_val, substring, 1, true) then
        error(red(("'" .. string_val .. "' !~ '" .. substring .. "'")))
    end
end

function Tx.throws(fn)
    local ok, _ = pcall(fn)
    if ok then
        error(red("Expected error to be thrown, but none was"))
    end
end

function Tx.fail(msg)
    error(msg or "Forced failure")
end

return Tx
