local term = require "term"
local bit  = require "bit"

-- Opcode values
local opcodes = {
    NOP    = 0x0,
    LOAD   = 0x1,
    STORE  = 0x2,
    ADDI   = 0x3,
    ADDR   = 0x4,
    SUBR   = 0x5,
    JMP    = 0x6,
    JMPZ   = 0x7,
    JMPN   = 0x8,
    NAND   = 0x9,
    SHIFTL = 0xA,
    SHIFTR = 0xB,
}

-- Which opcodes use a second 16-bit word
local twoCycle = {
    [0x1] = true,  -- LOAD   (address)
    [0x2] = true,  -- STORE  (address)
    [0x3] = true,  -- ADDI   (immediate)
}

-- Instruction syntax
local inst = {
    NOP    = { args = {},                 argTypes = {} },
    LOAD   = { args = {"Rd","Addr"},      argTypes = {"register","address"} },
    STORE  = { args = {"Rd","Addr"},      argTypes = {"register","address"} },
    ADDI   = { args = {"Rd","Rn","Imm"},  argTypes = {"register","register","immediate"} },
    ADDR   = { args = {"Rd","Rn","Rm"},   argTypes = {"register","register","register"} },
    SUBR   = { args = {"Rd","Rn","Rm"},   argTypes = {"register","register","register"} },
    JMP    = { args = {"Rd"},             argTypes = {"register"} },
    JMPZ   = { args = {"Rd"},             argTypes = {"register"} },
    JMPN   = { args = {"Rd"},             argTypes = {"register"} },
    NAND   = { args = {"Rd","Rn","Rm"},   argTypes = {"register","register","register"} },
    SHIFTL = { args = {"Rd","Rn"},        argTypes = {"register","register"} },
    SHIFTR = { args = {"Rd","Rn"},        argTypes = {"register","register"} },
}

--- Assemble a source file into an annotated listing and raw bytecode.
-- @param src  path to the .txt source
-- @return     listing (string), bytecode (string)
local function assemble(src)
    term.wipe()
    term.line("Assembling: " .. src)

    local annotated = {}   -- { { line=<srcLine>, hex={…} }, … }
    local maxLen    = 0

    for srcLine in io.open(src):lines() do
        term.line("Processing: " .. srcLine)
        -- tokenize, strip comments
        local words = {}
        for w in srcLine:gmatch("%S+") do
            if w:sub(1,2) == "--" then break end
            table.insert(words, w)
        end
        if #words == 0 then goto continue end

        local opname = words[1]:upper()
        local rule   = inst[opname]
        assert(rule, "Invalid instruction: " .. words[1])
        assert(#words-1 == #rule.args,
               "Expected "..#rule.args.." args for "..opname)

        -- parse arguments
        local vals = {}
        for i,argName in ipairs(rule.args) do
            local typ = rule.argTypes[i]
            local tok = words[i+1]
            assert(tok, opname.." missing arg "..i)
            local n
            if typ == "register" then
                assert(tok:match("^[rR]%d+$"),
                       opname.." register must be rN")
                n = tonumber(tok:sub(2))
                assert(n>=0 and n<=0xF,
                       opname.." register out of range")
            else
                n = tonumber(tok)
                assert(n and n>=0 and n<=0xFFFF,
                       opname.." value out of range")
            end
            vals[i] = n
        end

        -- encode into one or two 16-bit words
        local hexWords = {}
        local opc = opcodes[opname]
        local rd  = vals[1] or 0
        local rn  = vals[2] or 0
        local rm  = vals[3] or 0

        -- first word: [ opcode(4) | Rd(4) | Rn(4) | Rm(4) ]
        local w1 = bit.bor(
            bit.lshift(opc,12),
            bit.lshift(rd, 8),
            bit.lshift(rn, 4),
            rm
        )
        table.insert(hexWords, string.format("%04X", bit.band(w1,0xFFFF)))

        -- second word for LOAD/STORE/ADDI
        if twoCycle[opc] then
            local payload = vals[#vals]
            local w2 = bit.band(payload, 0xFFFF)
            table.insert(hexWords, string.format("%04X", w2))
        end

        annotated[#annotated+1] = { line = srcLine, hex = hexWords }
        maxLen = math.max(maxLen, #srcLine)
        ::continue::
    end

    -- build annotated listing
    local listingLines = {}
    local byteLines    = {}
    for _,row in ipairs(annotated) do
        local pad   = string.rep(" ", maxLen - #row.line + 2)
        local parts = {}
        for _,w in ipairs(row.hex) do
            table.insert(parts, "0x"..w)
            table.insert(byteLines, "0x"..w)
        end
        table.insert(listingLines,
            row.line .. pad .. "| " .. table.concat(parts, " ")
        )
    end

    local listing  = table.concat(listingLines, "\n")
    local bytecode = table.concat(byteLines,    "\n")
    return listing, bytecode
end

-- helper to pause on errors
local function waitSecond()
    local t0 = os.time()
    while os.time() - t0 < 1 do end
end

-- OS detection & directory setup
local isWin   = package.config:sub(1,1) == '\\'
local listCmd = isWin and 'dir /b "assemblerInput"' or 'ls "assemblerInput"'
local mkCmd   = isWin and 'if not exist "assemblerOutput" mkdir "assemblerOutput"' or 'mkdir -p "assemblerOutput"'
os.execute(mkCmd)

-- Assemble all files
local p = io.popen(listCmd)
assert(p, "Failed to list assemblerInput")
for filename in p:lines() do
    local src = "assemblerInput/" .. filename
    local fh  = io.open(src, "r")
    if fh then
        fh:close()
        local ok, listing, bytecode = pcall(assemble, src)
        if not ok then
            print("Error assembling " .. filename .. ": " .. tostring(listing))
            waitSecond()
        else
            -- print annotated listing
            print(listing)
            -- write raw bytecode
            local dest, err = io.open(
                "assemblerOutput/" .. filename:gsub("%.txt$", ".hex"),
                "w"
            )
            assert(dest, "Failed to open "..filename..": "..tostring(err))
            dest:write(bytecode)
            dest:close()
        end
    end
end
p:close()
