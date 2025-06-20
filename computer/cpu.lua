local CPU = {}

local bit = require "bit"

-- local state (single instance)
CPU.regs = {
    [1] = "0x0000", -- instruction register
    [2] = "0x0000", -- program counter
    [3] = "0x0000", -- bitwise flags
    [4] = "0x0000", -- first free register
    [5] = "0x0000",
    [6] = "0x0000",
    [7] = "0x0000",
    [8] = "0x0000",
    [9] = "0x0000",
    [10] = "0x0000",
    [11] = "0x0000",
    [12] = "0x0000",
    [13] = "0x0000",
    [14] = "0x0000",
    [15] = "0x0000",
    [16] = "0x0000"
}

local regs = CPU.regs
local r = CPU.regs

-- flag definitions
local FLAG_ZERO = 0x1 -- bit 0 of R3

-- combine two 8-bit bytes into a 16-bit word, masked to 0xFFFF
local function combineBytes(lo, hi)
    local w = bit.bor(lo, bit.lshift(hi, 8))
    return bit.band(w, 0xFFFF)
end

-- split a 16-bit word into low and high bytes
local function splitWord(val)
    return bit.band(val, 0xFF), bit.rshift(val, 8)
end

-- set or clear the zero flag (in regs[3])
local function setZeroFlag(val)
    if val == 0 then
        regs[3] = bit.bor(regs[3], FLAG_ZERO)
    else
        regs[3] = bit.band(regs[3], bit.bnot(FLAG_ZERO))
    end
end

-- return true if zero flag is set
local function getZeroFlag()
    return bit.band(regs[3], FLAG_ZERO) ~= 0
end


CPU.ops = {
    ---0x0000: NOP (no operation)
    ---@param _1 integer ignored
    ---@param _2 integer ignored
    ---@param _3 integer ignored
    [0x0000] = function(_1, _2, _3)
        print("NOP")
        -- no state change
    end,

    ---0x0001: SET register to immediate 16-bit value
    ---@param r integer register index (1–16)
    ---@param v integer 16-bit immediate value
    ---@param _3 integer ignored
    [0x0001] = function(r, v, _3)
        print(string.format("SET   R%d ← 0x%04X", r, v))
        regs[r] = v
        setZeroFlag(v)
    end,

    ---0x0002: LOAD from memory into register
    ---@param r integer register index (1–16)
    ---@param addr integer 16-bit memory address
    ---@param _3 integer ignored
    [0x0002] = function(r, addr, _3)
        local val = loadWord(addr)
        print(string.format("LOAD  R%d ← [0x%04X]  (0x%04X)", r, addr, val))
        regs[r] = val
        setZeroFlag(val)
    end,

    ---0x0003: STORE register into memory
    ---@param r integer register index (1–16)
    ---@param addr integer 16-bit memory address
    ---@param _3 integer ignored
    [0x0003] = function(r, addr, _3)
        local val = regs[r]
        print(string.format("STORE [0x%04X] ← R%d  (0x%04X)", addr, r, val))
        storeWord(addr, val)
    end,

    ---0x0004: ADD two registers
    ---@param d integer destination register index
    ---@param s1 integer source register1 index
    ---@param s2 integer source register2 index
    [0x0004] = function(d, s1, s2)
        local sum = regs[s1] + regs[s2]
        local res = bit.band(sum, 0xFFFF)
        print(string.format("ADD   R%d ← R%d + R%d  (0x%04X)", d, s1, s2, res))
        regs[d] = res
        setZeroFlag(res)
    end,

    ---0x0005: SUB subtract registers
    ---@param d integer destination register index
    ---@param s1 integer source register1 index
    ---@param s2 integer source register2 index
    [0x0005] = function(d, s1, s2)
        local diff = regs[s1] - regs[s2]
        local res  = bit.band(diff, 0xFFFF)
        print(string.format("SUB   R%d ← R%d - R%d  (0x%04X)", d, s1, s2, res))
        regs[d] = res
        setZeroFlag(res)
    end,

    ---0x0006: MUL multiply registers
    ---@param d integer destination register index
    ---@param s1 integer source register1 index
    ---@param s2 integer source register2 index
    [0x0006] = function(d, s1, s2)
        local prod = regs[s1] * regs[s2]
        local res  = bit.band(prod, 0xFFFF)
        print(string.format("MUL   R%d ← R%d * R%d  (0x%04X)", d, s1, s2, res))
        regs[d] = res
        setZeroFlag(res)
    end,

    ---0x0007: DIV integer division (avoid divide by zero)
    ---@param d integer destination register index
    ---@param s1 integer source register1 index
    ---@param s2 integer source register2 index
    [0x0007] = function(d, s1, s2)
        local denom = regs[s2] == 0 and 1 or regs[s2]
        local quot  = math.floor(regs[s1] / denom)
        local res   = bit.band(quot, 0xFFFF)
        print(string.format("DIV   R%d ← R%d / R%d  (0x%04X)", d, s1, s2, res))
        regs[d] = res
        setZeroFlag(res)
    end,

    ---0x0008: AND bitwise
    ---@param d integer destination register index
    ---@param s1 integer source register1 index
    ---@param s2 integer source register2 index
    [0x0008] = function(d, s1, s2)
        local res = bit.band(regs[s1], regs[s2])
        print(string.format("AND   R%d ← R%d & R%d  (0x%04X)", d, s1, s2, res))
        regs[d] = res
        setZeroFlag(res)
    end,

    ---0x0009: OR bitwise
    ---@param d integer destination register index
    ---@param s1 integer source register1 index
    ---@param s2 integer source register2 index
    [0x0009] = function(d, s1, s2)
        local res = bit.bor(regs[s1], regs[s2])
        print(string.format("OR    R%d ← R%d | R%d  (0x%04X)", d, s1, s2, res))
        regs[d] = res
        setZeroFlag(res)
    end,

    ---0x000A: XOR bitwise
    ---@param d integer destination register index
    ---@param s1 integer source register1 index
    ---@param s2 integer source register2 index
    [0x000A] = function(d, s1, s2)
        local res = bit.bxor(regs[s1], regs[s2])
        print(string.format("XOR   R%d ← R%d ~ R%d  (0x%04X)", d, s1, s2, res))
        regs[d] = res
        setZeroFlag(res)
    end,

    ---0x000B: NOT bitwise
    ---@param d integer destination register index
    ---@param s integer source register index
    ---@param _3 integer ignored
    [0x000B] = function(d, s, _3)
        local inv = bit.bnot(regs[s])
        local res = bit.band(inv, 0xFFFF)
        print(string.format("NOT   R%d ← ~R%d      (0x%04X)", d, s, res))
        regs[d] = res
        setZeroFlag(res)
    end,

    ---0x000C: JMP unconditional
    ---@param addr integer 16-bit jump address
    ---@param _2 integer ignored
    ---@param _3 integer ignored
    [0x000C] = function(addr, _2, _3)
        print(string.format("JMP   PC ← 0x%04X", addr))
        regs[2] = addr  -- R2 is program counter
    end,

    ---0x000D: JZ jump if zero flag set
    ---@param addr integer 16-bit jump address
    ---@param _2 integer ignored
    ---@param _3 integer ignored
    [0x000D] = function(addr, _2, _3)
        if getZeroFlag() then
            print(string.format("JZ    PC ← 0x%04X (zero)", addr))
            regs[2] = addr
        else
            print("JZ    skipped (non-zero)")
        end
    end,

    ---0x000E: JNZ jump if zero flag not set
    ---@param addr integer 16-bit jump address
    ---@param _2 integer ignored
    ---@param _3 integer ignored
    [0x000E] = function(addr, _2, _3)
        if not getZeroFlag() then
            print(string.format("JNZ   PC ← 0x%04X (non-zero)", addr))
            regs[2] = addr
        else
            print("JNZ   skipped (zero)")
        end
    end,

    ---0x000F: HALT execution
    ---@param _1 integer ignored
    ---@param _2 integer ignored
    ---@param _3 integer ignored
    [0x000F] = function(_1, _2, _3)
        print("HALT")
        error("HALT")
    end,
}
