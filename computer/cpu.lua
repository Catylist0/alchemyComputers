CPU = {}

local bit = require "bit"

-- register definitions
local registers = {
    R1 = true, -- instruction register
    R2 = true, -- program counter
    R3 = true, -- bitwise flags (bit 0 = zero flag)
    R4 = true,
    R5 = true,
    R6 = true,
    R7 = true,
    R8 = true,
    R9 = true,
    R10 = true,
    R11 = true,
    R12 = true,
    R13 = true,
    R14 = true,
    R15 = true,
    R16 = true
}

-- map numeric codes 0–15 to register names R1–R16
local regNames = {
    [0] = "R1",
    [1] = "R2",
    [2] = "R3",
    [3] = "R4",
    [4] = "R5",
    [5] = "R6",
    [6] = "R7",
    [7] = "R8",
    [8] = "R9",
    [9] = "R10",
    [10] = "R11",
    [11] = "R12",
    [12] = "R13",
    [13] = "R14",
    [14] = "R15",
    [15] = "R16"
}

-- helper: combine two bytes into 16-bit word
local function toWord(lo, hi)
    return bit.bor(lo, bit.lshift(hi, 8))
end

-- flag helpers: zero flag is bit 0 of R3
local function setZeroFlag(cpu, value)
    if value == 0 then
        cpu.reg.R3 = bit.bor(cpu.reg.R3, 1)
    else
        cpu.reg.R3 = bit.band(cpu.reg.R3, bit.bnot(1))
    end
end

local function zeroFlag(cpu)
    return bit.band(cpu.reg.R3, 1) == 1
end

-- CPU.ops dispatch table, using minimal 'cpu' instead of 'self'
CPU.ops = {
    [0x00] = function()
    end,

    [0x01] = function(cpu, r, lo, hi)
        local rn = regNames[r]
        local v = toWord(lo, hi)
        cpu.reg[rn] = v
        setZeroFlag(cpu, v)
    end,

    [0x02] = function(cpu, r, lo, hi)
        local addr = toWord(lo, hi)
        local lo8 = cpu.mem:load(addr)
        local hi8 = cpu.mem:load((addr + 1) & 0xFFFF)
        local v = toWord(lo8, hi8)
        cpu.reg[regNames[r]] = v
        setZeroFlag(cpu, v)
    end,

    [0x03] = function(cpu, r, lo, hi)
        local addr = toWord(lo, hi)
        local v = cpu.reg[regNames[r]]
        cpu.mem:store(addr, bit.band(v, 0xFF))
        cpu.mem:store((addr + 1) & 0xFFFF, bit.rshift(v, 8))
    end,

    [0x04] = function(cpu, d, s1, s2)
        local a = cpu.reg[regNames[s1]]
        local b = cpu.reg[regNames[s2]]
        local res = (a + b) & 0xFFFF
        cpu.reg[regNames[d]] = res
        setZeroFlag(cpu, res)
    end,

    [0x05] = function(cpu, d, s1, s2)
        local a = cpu.reg[regNames[s1]]
        local b = cpu.reg[regNames[s2]]
        local res = (a - b) & 0xFFFF
        cpu.reg[regNames[d]] = res
        setZeroFlag(cpu, res)
    end,

    [0x06] = function(cpu, d, s1, s2)
        local a = cpu.reg[regNames[s1]]
        local b = cpu.reg[regNames[s2]]
        local res = (a * b) & 0xFFFF
        cpu.reg[regNames[d]] = res
        setZeroFlag(cpu, res)
    end,

    [0x07] = function(cpu, d, s1, s2)
        local a = cpu.reg[regNames[s1]]
        local b = cpu.reg[regNames[s2]]
        local res = math.floor(a / (b == 0 and 1 or b)) & 0xFFFF
        cpu.reg[regNames[d]] = res
        setZeroFlag(cpu, res)
    end,

    [0x08] = function(cpu, d, s1, s2)
        local res = bit.band(cpu.reg[regNames[s1]], cpu.reg[regNames[s2]])
        cpu.reg[regNames[d]] = res
        setZeroFlag(cpu, res)
    end,

    [0x09] = function(cpu, d, s1, s2)
        local res = bit.bor(cpu.reg[regNames[s1]], cpu.reg[regNames[s2]])
        cpu.reg[regNames[d]] = res
        setZeroFlag(cpu, res)
    end,

    [0x0A] = function(cpu, d, s1, s2)
        local res = bit.bxor(cpu.reg[regNames[s1]], cpu.reg[regNames[s2]])
        cpu.reg[regNames[d]] = res
        setZeroFlag(cpu, res)
    end,

    [0x0B] = function(cpu, d, s, _)
        local v = bit.bnot(cpu.reg[regNames[s]]) & 0xFFFF
        cpu.reg[regNames[d]] = v
        setZeroFlag(cpu, v)
    end,

    [0x0C] = function(cpu, lo, hi)
        cpu.PC = toWord(lo, hi)
    end,

    [0x0D] = function(cpu, lo, hi)
        if zeroFlag(cpu) then
            cpu.PC = toWord(lo, hi)
        end
    end,

    [0x0E] = function(cpu, lo, hi)
        if not zeroFlag(cpu) then
            cpu.PC = toWord(lo, hi)
        end
    end,

    [0x0F] = function()
        error("HALT")
    end
}
