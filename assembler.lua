-- Assembler.lua
Assembler = {}

local bit = require "bit"

local OPCODES = {
    NOP   = 0x0000,
    SET   = 0x0001,
    LOAD  = 0x0002,
    STORE = 0x0003,
    ADD   = 0x0004,
    SUB   = 0x0005,
    MUL   = 0x0006,
    DIV   = 0x0007,
    AND   = 0x0008,
    OR    = 0x0009,
    XOR   = 0x000A,
    NOT   = 0x000B,
    JMP   = 0x000C,
    JZ    = 0x000D,
    JNZ   = 0x000E,
    HALT  = 0x000F,
}

local SyntaxLookup = {
    [0x0000] = { mnemonic = "NOP",  syntax = "NOP"               },
    [0x0001] = { mnemonic = "SET",  syntax = "SET  R<r> , <v>"   },
    [0x0002] = { mnemonic = "LOAD", syntax = "LOAD R<r> , [0x<addr>]" },
    [0x0003] = { mnemonic = "STORE",syntax = "STORE [0x<addr>] , R<r>" },
    [0x0004] = { mnemonic = "ADD",  syntax = "ADD  R<d> , R<s1> , R<s2>" },
    [0x0005] = { mnemonic = "SUB",  syntax = "SUB  R<d> , R<s1> , R<s2>" },
    [0x0006] = { mnemonic = "MUL",  syntax = "MUL  R<d> , R<s1> , R<s2>" },
    [0x0007] = { mnemonic = "DIV",  syntax = "DIV  R<d> , R<s1> , R<s2>" },
    [0x0008] = { mnemonic = "AND",  syntax = "AND  R<d> , R<s1> , R<s2>" },
    [0x0009] = { mnemonic = "OR",   syntax = "OR   R<d> , R<s1> , R<s2>" },
    [0x000A] = { mnemonic = "XOR",  syntax = "XOR  R<d> , R<s1> , R<s2>" },
    [0x000B] = { mnemonic = "NOT",  syntax = "NOT  R<d> , R<s>"      },
    [0x000C] = { mnemonic = "JMP",  syntax = "JMP  0x<addr>"        },
    [0x000D] = { mnemonic = "JZ",   syntax = "JZ   0x<addr>"        },
    [0x000E] = { mnemonic = "JNZ",  syntax = "JNZ  0x<addr>"        },
    [0x000F] = { mnemonic = "HALT", syntax = "HALT"               },
}

--- Parses a single line of assembly, validates syntax, and appends 4 words to bytecodechunks.
---@param line string Assembly source line
---@param lineNum integer Line number in source (for error reporting)
---@param bytecodechunks table Array to append 16-bit words to
local function parseLine(line, lineNum, bytecodechunks)
    -- collect tokens until a comment or end‐of‐line
    local tokens = {}
    for token in line:gmatch("%S+") do
        if token:sub(1,2) == "--" then break end
        tokens[#tokens+1] = token
    end

    if #tokens == 0 then
        -- blank or comment‐only line: no output
        return
    end

    -- lookup opcode
    local mnem   = tokens[1]
    local opcode = OPCODES[mnem]
    if not opcode then
        error(("Line %d: Unknown opcode '%s'"):format(lineNum, mnem), 0)
    end

    -- lookup expected syntax
    local entry = SyntaxLookup[opcode]
    if not entry then
        error(("Line %d: No syntax for opcode 0x%04X"):format(lineNum, opcode), 0)
    end

    -- count expected operands by counting placeholders in syntax string
    local expected = 0
    for _ in entry.syntax:gmatch("<%w+>") do expected = expected + 1 end

    -- count actual operands
    local actual = #tokens - 1
    if actual < expected then
        error(("Line %d: Too few operands for '%s' - expected %d, got %d"):format(
            lineNum, mnem, expected, actual
        ), 0)
    end
    if actual > expected then
        error(("Line %d: Too many operands for '%s' - expected %d, got %d"):format(
            lineNum, mnem, expected, actual
        ), 0)
    end

    -- build this instruction's words
    local chunks = { opcode }
    for i = 1, expected do
        local tok = tokens[i+1]
        if tok:sub(1,1):lower() == "r" then
            -- register operand
            local idx = tonumber(tok:sub(2))
            if not idx or idx < 1 or idx > 16 then
                error(("Line %d: Invalid register '%s'"):format(lineNum, tok), 0)
            end
            chunks[#chunks+1] = idx
        else
            -- immediate/address operand
            local num = tonumber(tok)
            if not num then
                error(("Line %d: Invalid operand '%s'"):format(lineNum, tok), 0)
            end
            chunks[#chunks+1] = bit.band(num, 0xFFFF)
        end
    end

    -- pad to exactly 4 words
    while #chunks < 4 do
        chunks[#chunks+1] = 0x0000
    end

    -- append into the global bytecode array
    for _, w in ipairs(chunks) do
        bytecodechunks[#bytecodechunks+1] = w
    end
end

--- Encodes a multi-line assembly string into a flat array of 16-bit words.
---@param src string Assembly source text
---@return table Array of 16-bit words
local function encode(src)
    local bytecode = {}
    local lineNum  = 0

    for line in src:gmatch("[^\r\n]+") do
        lineNum = lineNum + 1
        -- catch and rethrow errors without full traceback
        local ok, err = pcall(parseLine, line, lineNum, bytecode)
        if not ok then
            error(err, 0)
        end
    end

    return bytecode
end

--- Stub for future decode functionality.
---@param bytecode table Array of 16-bit words
local function decode(bytecode)
    -- your decode logic here
end

--- Reads 'rom.txt', assembles it, and writes raw 16-bit words into 'rom.byte'.
function Assembler.updateRom()
    local inFile = assert(io.open("emulatorInstructions/rom.txt", "r"))
    local src    = inFile:read("*a")
    inFile:close()

    local bytecode = encode(src)
    local outFile  = assert(io.open("bytecode/rom.byte", "wb"))

    for _, v in ipairs(bytecode) do
        local high = bit.band(bit.rshift(v, 8), 0xFF)
        local low  = bit.band(v,        0xFF)
        outFile:write(string.char(high, low))
    end

    outFile:close()
    print("EMULATOR: ROM updated with new bytecode. (This is for dev purposes because ROM is read-only)")
end
