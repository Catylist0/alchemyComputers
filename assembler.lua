local bit = require "bit"
local OPCODES = {
    NOP = 0x0000,
    SET = 0x0001,
    LOAD = 0x0002,
    STORE = 0x0003,
    ADD = 0x0004,
    SUB = 0x0005,
    MUL = 0x0006,
    DIV = 0x0007,
    AND = 0x0008,
    OR = 0x0009,
    XOR = 0x000A,
    NOT = 0x000B,
    JMP = 0x000C,
    JZ = 0x000D,
    JNZ = 0x000E,
    HALT = 0x000F
}

local function parseLine(line, bytecodechunks)
    local chunks = {}

    for token in line:gmatch("%S+") do
        if token:sub(1, 2) == "--" then
            break
        end

        if OPCODES[token] then
            table.insert(chunks, OPCODES[token])

        elseif #chunks == 0 then
            error("Unknown opcode: " .. token)

        elseif token:sub(1, 1):lower() == "r" then
            local idx = tonumber(token:sub(2))
            if not idx or idx < 1 or idx > 16 then
                error("Invalid register: " .. token)
            end
            table.insert(chunks, idx)

        else
            local num = tonumber(token)
            if not num then
                -- unrecognized → null
                table.insert(chunks, 0x0000)
            else
                -- immediate/address
                num = bit.band(num, 0xFFFF)
                table.insert(chunks, num)
            end
        end
    end

    -- append to bytecode
    for _, v in ipairs(chunks) do
        table.insert(bytecodechunks, v)
    end
end

local function encode(src)
    local bytecode = {}
    for line in src:gmatch("[^\r\n]+") do
        parseLine(line, bytecode)
    end
    return bytecode
end

-- decode stub
local function decode(bytecode)
    -- your decode logic here
end
