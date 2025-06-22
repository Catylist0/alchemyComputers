local Hardware = {}

Hardware.bus = {
    instruction = 0x0000,
    data = 0x0000
}

Hardware.cpu = {}
local cpu = Hardware.cpu

cpu.miscMemory = {
    programCounter = 0x0000, -- holds the address of the next instruction to execute
    flagWasNegative = false, -- boolean flag indicating if the last instruction resulted in a negative value
    flagWasZero = false, -- boolean flag indicating if the last instruction resulted in a zero value
}

cpu.registers = {
    [0x0] = 0x0000, -- r0: reserved for zero value. Writing to this register does nothing and is a form of nop.
    [0x1] = 0x0000, -- r1: link register
    [0x2] = 0x0000, -- r2: first free register
    [0x3] = 0x0000,
    [0x4] = 0x0000,
    [0x5] = 0x0000,
    [0x6] = 0x0000,
    [0x7] = 0x0000,
    [0x8] = 0x0000,
    [0x9] = 0x0000,
    [0xA] = 0x0000,
    [0xB] = 0x0000,
    [0xC] = 0x0000,
    [0xD] = 0x0000,
    [0xE] = 0x0000,
    [0xF] = 0x0000
}

cpu.decoder = {
    overflowRegister = 0x0000, -- holds the overflow value from the last operation if need be
    overflowFlag = false, -- boolean flag indicating if the last operation resulted in an overflow
    action = function()
    end
}

do
    local function fetch()
        
    end

    local function decode()

    end

    local function execute()

    end

    local function writeBack()

    end

    function CPU.cycle()

    end
end

return CPU