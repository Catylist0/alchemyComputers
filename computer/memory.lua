Memory = {}

local RAM = {}

-- Load the ROM as bytecode from bytecode/rom.txt
local f = assert(io.open("bytecode/rom.byte", "r"))
local ROM = f:read("*a")

f:close()
