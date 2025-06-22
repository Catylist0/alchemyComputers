local handle = io.popen("stty size", "r")
local output = handle:read("*l")
handle:close()

local rows, cols = output:match("^(%d+)%s+(%d+)$")
rows = tonumber(rows)
cols = tonumber(cols)

-- Clear screen and move cursor to bottom-left
io.write("\27[2J", string.format("\27[%d;1H", rows))