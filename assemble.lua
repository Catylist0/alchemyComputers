local term            = require "term"

-- Syntax and instruction definitions
local syntaxRules     = {}
local inst            = syntaxRules

syntaxRules.dataTypes = {
    address   = { words = 4, type = "address" },
    register  = { words = 1, type = "register" },
    immediate = { words = 4, type = "immediate" },
}

inst.NOP              = { name = "NOP", args = {}, argTypes = {} }
inst.LOAD             = { name = "LOAD", args = { "Rd", "address" }, argTypes = { "register", "address" } }
inst.STORE            = { name = "STORE", args = { "Rd", "address" }, argTypes = { "register", "address" } }
inst.ADDI             = { name = "ADDI", args = { "Rd", "Rn", "Imm" }, argTypes = { "register", "register", "immediate" } }
inst.ADDR             = { name = "ADDR", args = { "Rd", "Rn", "Rm" }, argTypes = { "register", "register", "register" } }
inst.SUBR             = { name = "SUBR", args = { "Rd", "Rn", "Rm" }, argTypes = { "register", "register", "register" } }
inst.JMP              = { name = "JMP", args = { "address" }, argTypes = { "address" } }
inst.JMPZ             = { name = "JMPZ", args = { "address" }, argTypes = { "address" } }
inst.JMPN             = { name = "JMPN", args = { "address" }, argTypes = { "address" } }
inst.NAND             = { name = "NAND", args = { "Rd", "Rn", "Rm" }, argTypes = { "register", "register", "register" } }
inst.SHIFTL           = { name = "SHIFTL", args = { "Rd", "Rn" }, argTypes = { "register", "register" } }
inst.SHIFTR           = { name = "SHIFTR", args = { "Rd", "Rn" }, argTypes = { "register", "register" } }

-- Assembler function
local function assemble(src)
    local f = io.open(src, "r")
    assert(f, "Could not open source file: " .. src)
    local content = f:read("*a")
    f:close()

    local outLines = {}
    for line in content:gmatch("[^\r\n]+") do
        local words = {}
        for w in line:gmatch("%S+") do
            if w:sub(1, 2) == "--" then break end
            table.insert(words, w)
        end
        if #words == 0 then goto continue end

        local opname = words[1]:upper()
        local rule   = inst[opname]
        assert(rule, "Invalid instruction: " .. words[1] .. " in line: " .. line)
        assert(#words - 1 == #rule.args,
            "Bad arg count for " .. opname .. " in line: " .. line)

        local vals = {}
        for i, argName in ipairs(rule.args) do
            local typ = rule.argTypes[i]
            local tok = words[i + 1]
            assert(tok, "Missing arg " .. i .. " for " .. opname)
            local n = tonumber(tok)
            assert(n, "Invalid number '" .. tok .. "' for " .. opname)
            if typ == "register" then
                assert(n >= 0 and n <= 0xF,
                    opname .. " register out of range: " .. tok)
            elseif typ == "address" or typ == "immediate" then
                assert(n >= 0 and n <= 0xFFFFFFFF,
                    opname .. " value out of range: " .. tok)
            end
            vals[i] = n
        end

        local hexChunks = {}
        for i, argName in ipairs(rule.args) do
            local typ = rule.argTypes[i]
            local dt  = syntaxRules.dataTypes[typ]
            local w   = dt.words
            local v   = vals[i]
            local hex = string.format("%0" .. (w * 2) .. "X", v)
            for j = 1, #hex, 2 do
                table.insert(hexChunks, hex:sub(j, j + 1))
            end
        end

        table.insert(outLines, table.concat(hexChunks))
        ::continue::
    end

    return table.concat(outLines, "\n")
end

-- OS detection and directory setup
local isWindows = package.config:sub(1, 1) == '\\'
local listCmd   = isWindows and 'dir /b "assemblerInput"' or 'ls "assemblerInput"'
local mkdirCmd  = isWindows and 'if not exist "assemblerOutput" mkdir "assemblerOutput"' or 'mkdir -p "assemblerOutput"'

os.execute(mkdirCmd)

-- Assemble all files
local p = io.popen(listCmd)
assert(p, "Failed to list assemblerInput")

for filename in p:lines() do
    local src = "assemblerInput/" .. filename
    local infile = io.open(src, "r")
    if infile then
        infile:close()
        local assembled = assemble(src)
        local dest = "assemblerOutput/" .. filename:gsub("%.txt$", ".hex")
        local out, err = io.open(dest, "w")
        assert(out, "Failed to open " .. dest .. ": " .. tostring(err))
        out:write(assembled)
        out:close()
    end
end

p:close()
