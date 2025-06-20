CPU = {}

-- ==================== REGISTERS ====================
local registers = { -- 16bit registers
    R1 = true, -- instruction register
    R2 = true, -- program counter
    R3 = true, -- flags
    R4 = true, -- first free register
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

for i, register in pairs(registers) do
    local blankRegister = {}
    for j = 1, 16 do
        blankRegister[j] = false
    end
    registers[i] = blankRegister
end

-- ==================== INSTRUCITON OPERATION ====================

-- dispatch table
CPU.ops = {
    [0x00] = function()
    end,
    [0x01] = function(self, r, lo, hi)
        self.reg[r] = bit32.bor(lo, bit32.lshift(hi, 8))
        self.zero_flag = (self.reg[r] == 0)
    end,
    [0x02] = function(self, r, lo, hi)
        local addr = bit32.bor(lo, bit32.lshift(hi, 8))
        local lo8 = self.mem:load(addr)
        local hi8 = self.mem:load((addr + 1) & 0xFFFF)
        self.reg[r] = bit32.bor(lo8, bit32.lshift(hi8, 8))
        self.zero_flag = (self.reg[r] == 0)
    end,
    [0x03] = function(self, r, lo, hi)
        local addr = bit32.bor(lo, bit32.lshift(hi, 8))
        local val = self.reg[r]
        self.mem:store(addr, bit32.band(val, 0xFF))
        self.mem:store((addr + 1) & 0xFFFF, bit32.rshift(val, 8))
    end,
    [0x04] = function(self, d, s1, s2)
        local res = (self.reg[s1] + self.reg[s2]) & 0xFFFF
        self.reg[d], self.zero_flag = res, (res == 0)
    end,
    [0x05] = function(self, d, s1, s2)
        local res = (self.reg[s1] - self.reg[s2]) & 0xFFFF
        self.reg[d], self.zero_flag = res, (res == 0)
    end,
    [0x06] = function(self, d, s1, s2)
        local res = (self.reg[s1] * self.reg[s2]) & 0xFFFF
        self.reg[d], self.zero_flag = res, (res == 0)
    end,
    [0x07] = function(self, d, s1, s2)
        local res = math.floor(self.reg[s1] / (self.reg[s2] == 0 and 1 or self.reg[s2]))
        self.reg[d], self.zero_flag = res & 0xFFFF, (res == 0)
    end,
    [0x08] = function(self, d, s1, s2)
        local res = bit32.band(self.reg[s1], self.reg[s2])
        self.reg[d], self.zero_flag = res, (res == 0)
    end,
    [0x09] = function(self, d, s1, s2)
        local res = bit32.bor(self.reg[s1], self.reg[s2])
        self.reg[d], self.zero_flag = res, (res == 0)
    end,
    [0x0A] = function(self, d, s1, s2)
        local res = bit32.bxor(self.reg[s1], self.reg[s2])
        self.reg[d], self.zero_flag = res, (res == 0)
    end,
    [0x0B] = function(self, d, s, _)
        local res = bit32.bnot(self.reg[s]) & 0xFFFF
        self.reg[d], self.zero_flag = res, (res == 0)
    end,
    [0x0C] = function(self, lo, hi)
        self.PC = bit32.bor(lo, bit32.lshift(hi, 8))
    end,
    [0x0D] = function(self, lo, hi)
        if self.zero_flag then
            self.PC = bit32.bor(lo, bit32.lshift(hi, 8))
        end
    end,
    [0x0E] = function(self, lo, hi)
        if not self.zero_flag then
            self.PC = bit32.bor(lo, bit32.lshift(hi, 8))
        end
    end,
    [0x0F] = function(self)
        error("HALT")
    end
}

-- Entrypoint
