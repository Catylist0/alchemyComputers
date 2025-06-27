local term = {}
local buf = {}
local rows, cols = 0, 0

local socket = require "socket"
local benchmarks = {} -- store count and total time for each function

local function now()
    return JIT_TIME()
end

local function record(name, dt)
    local b = benchmarks[name]
    if not b then
        b = { count = 0, sum = 0 }
    end
    b.count = b.count + 1
    b.sum = b.sum + dt
    benchmarks[name] = b
end

local function getSize()
    local t0 = now()
    local handle = io.popen("stty size", "r")
    local out = handle:read("*l")
    handle:close()
    local r, c = out:match("^(%d+)%s+(%d+)$")
    rows = tonumber(r) or rows
    cols = tonumber(c) or cols
    record("getSize", now() - t0)
end

-- Clears the buffer and updates terminal size
function term.wipe()
    local t0 = now()
    getSize()
    buf = {}
    record("wipe", now() - t0)
end

-- Appends a line to the buffer
function term.line(content)
    local t0 = now()
    buf[#buf + 1] = content
    record("line", now() - t0)
end

-- Centers text within the current terminal width
function term.center(str)
    local t0 = now()
    local len = #str
    local result
    if len >= cols then
        result = str
    else
        local pad = math.floor((cols - len) / 2)
        result = string.rep(" ", pad) .. str
    end
    record("center", now() - t0)
    return result
end

-- Right-aligns text within the current terminal width
function term.right(str)
    local t0 = now()
    local len = #str
    local result
    if len >= cols then
        result = str
    else
        local pad = cols - len
        result = string.rep(" ", pad) .. str
    end
    record("right", now() - t0)
    return result
end

-- adds a specified padding amount to the left of the string
function term.padLeft(str, padding)
    local t0 = now()
    local len = #str
    local result
    if len >= cols then
        result = str
    else
        local pad = (padding or 0) * 2 -- double the padding for better visibility
        result = string.rep(" ", pad) .. str
    end
    record("padLeft", now() - t0)
    return result
end

local prev_buf = {}
local firstRender = true

function term.render()
    local t0 = now()
    getSize()
    if firstRender then
        io.write("\27[2J")      -- clear screen once
        firstRender = false
    end
    io.write("\27[?25l")       -- hide cursor
    io.write("\27[H")          -- home cursor
    local out = {}
    for i = 1, rows do
        local line = buf[i] or ""
        if line ~= prev_buf[i] then
            out[#out+1] = ("\27[%d;1H%s\27[K"):format(i, line)
            prev_buf[i] = line
        end
    end
    io.write(table.concat(out))
    io.write(("\27[%d;1H"):format(rows)) -- leave cursor at bottom
    io.write("\27[?25h")                 -- show cursor
    record("render", now() - t0)
end

function term.printBenchmarks()
    local t0 = now()
    print("Benchmark Results:")
    for name, b in pairs(benchmarks) do
        local avg = b.sum / b.count
        print(string.format("%s: %d calls, avg %.6f seconds\n", name, b.count, avg))
    end
    record("printBenchmarks", now() - t0)
end

return term
