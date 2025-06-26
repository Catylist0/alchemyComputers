local Hardware = {}
local bit = require("bit")

Hardware.bus = {
    data = 0x0000, -- data bus
    address = 0x0000, -- address bus
    writeLine = false, -- boolean flag indicating if the bus is in a read cycle
    resetLine = false, -- boolean flag indicating if the reset line is active
    clock = true, -- boolean flag indicating if the clock is high
}

Hardware.mem = {}

function formatMem()
    for i = 0x0100, 0xFFFF do -- the first 256 bytes are reserved for the ROM firmware
        Hardware.mem[i] = 0x0000 -- Initialize mem with zeroes
    end
    Hardware.mem[0x0000] = 0x0000 -- Initialize the first byte to nop (Temporary)
end

do
    local mem = Hardware.mem

    function mem.read()
        if Hardware.bus.writeLine then
            return nil
        end -- If the bus is in a write cycle, do nothing
        local address = Hardware.bus.address
        local value = mem[address]
        Hardware.bus.data = value
    end

    function mem.write()
        if not Hardware.bus.writeLine then
            return nil
        end -- If the bus is not in a write cycle, do nothing
        local address = Hardware.bus.address
        local value = Hardware.bus.data
        mem[address] = value
    end
end

Hardware.cpu = {}
do
    local cpu = Hardware.cpu

    cpu.miscMemory = {
        programCounter = 0x0000, -- holds the address of the next instruction to execute
        flagWasNegative = false, -- boolean flag indicating if the last instruction resulted in a negative value
        flagWasZero = false, -- boolean flag indicating if the last instruction resulted in a zero value
        shouldAdvancePC = false -- boolean flag indicating if the program counter should not be advanced
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
        twoCycleOpcodes = {
            [0x1] = true, -- LOAD   (24-bit)
            [0x2] = true, -- STORE  (24-bit)
            [0x3] = true, -- ADDI   (28-bit)
            [0x6] = true, -- JMP    (20-bit)
            [0x7] = true, -- JMPZ   (20-bit)
            [0x8] = true -- JMPN   (20-bit)
        },
        pendingFetch = false,
        overflowRegister = 0x0000, -- holds entire first 16-bit fetch
        opcodeBus = 0x0,
        destinationBus = 0x0,
        contentBus = 0x000000,

        decode = function()
            local raw = Hardware.bus.data -- first 16 bits

            if not cpu.decoder.pendingFetch then
                local top = bit.rshift(raw, 12)
                local dest = bit.band(bit.rshift(raw, 8), 0xF)

                cpu.decoder.opcodeBus = top
                cpu.decoder.destinationBus = dest

                if cpu.decoder.twoCycleOpcodes[top] then
                    cpu.decoder.pendingFetch = true
                    cpu.decoder.overflowRegister = raw
                    cpu.clock = false
                    return
                end

                cpu.decoder.contentBus = bit.band(raw, 0xFF)
                return
            end

            -- second half
            local ext = Hardware.bus.data
            local first = cpu.decoder.overflowRegister
            local low = bit.band(first, 0xFF)

            cpu.decoder.opcodeBus = bit.rshift(first, 12)
            cpu.decoder.destinationBus = bit.band(bit.rshift(first, 8), 0xF)
            cpu.decoder.contentBus = bit.bor(bit.lshift(low, 16), bit.band(ext, 0xFFFF))

            cpu.decoder.pendingFetch = false
        end
    }

    local function combineNibbles(args, start, count)
        local v = 0
        for i = 0, count - 1 do
            v = bit.bor(v, bit.lshift(args[start + i], i * 4))
        end
        return v
    end

    cpu.instructions = {
        [0x0] = function(rd, args)
            -- NOP: nothing
        end,

        [0x1] = function(rd, args)
            -- LOAD Rd, addr24
            local addr = combineNibbles(args, 1, 6)  -- use args[1..6]
            Hardware.bus.writeLine = false
            Hardware.bus.address   = addr
            Hardware.mem.read()
            Hardware.cpu.registers[rd] = Hardware.bus.data
            Hardware.bus.data    = 0
            Hardware.bus.address = 0
        end,

        [0x2] = function(rd, args)
            -- STORE Rd, addr24
            local addr = combineNibbles(args, 1, 6)
            Hardware.bus.writeLine = true
            Hardware.bus.address   = addr
            Hardware.bus.data      = Hardware.cpu.registers[rd]
            Hardware.mem.write()
            Hardware.bus.writeLine = false
            Hardware.bus.data      = 0
            Hardware.bus.address   = 0
        end,

        [0x3] = function(rd, args)
            -- ADDI Rd, Rn, imm20
            local rn  = args[1]
            local imm = combineNibbles(args, 2, 5)  -- args[2..6]
            Hardware.cpu.registers[rd] = Hardware.cpu.registers[rn] + imm
        end,

        [0x4] = function(rd, args)
            -- ADDR Rd, Rn, Rm
            local rn = args[2]
            local rm = args[1]
            Hardware.cpu.registers[rd] = Hardware.cpu.registers[rn] + Hardware.cpu.registers[rm]
        end,

        [0x5] = function(rd, args)
            -- SUBR Rd, Rn, Rm
            local rn  = args[2]
            local rm  = args[1]
            local res = Hardware.cpu.registers[rn] - Hardware.cpu.registers[rm]
            Hardware.cpu.miscMemory.flagWasZero     = (res == 0)
            Hardware.cpu.miscMemory.flagWasNegative = (res < 0)
            Hardware.cpu.registers[rd]              = res
        end,

        [0x6] = function(rd, args)
            -- JMP addr20
            Hardware.cpu.miscMemory.shouldAdvancePC = false
            local addr = combineNibbles(args, 1, 5)  -- args[1..5]
            Hardware.cpu.miscMemory.programCounter = addr
            Hardware.cpu.registers[0x1] = addr
        end,

        [0x7] = function(rd, args)
            -- JMPZ addr20
            Hardware.cpu.miscMemory.shouldAdvancePC = false
            local addr = combineNibbles(args, 1, 5)
            if Hardware.cpu.miscMemory.flagWasZero then
                Hardware.cpu.miscMemory.programCounter = addr
            end
        end,

        [0x8] = function(rd, args)
            -- JMPN addr20
            Hardware.cpu.miscMemory.shouldAdvancePC = false
            local addr = combineNibbles(args, 1, 5)
            if Hardware.cpu.miscMemory.flagWasNegative then
                Hardware.cpu.miscMemory.programCounter = addr
            end
        end,

        [0x9] = function(rd, args)
            -- NAND Rd, Rn, Rm
            local rn = args[2]
            local rm = args[1]
            Hardware.cpu.registers[rd] =
                bit.bnot(bit.band(Hardware.cpu.registers[rn], Hardware.cpu.registers[rm]))
        end,

        [0xA] = function(rd, args)
            -- SHIFTL Rd, Rn
            local rn = args[2]
            Hardware.cpu.registers[rd] = bit.lshift(Hardware.cpu.registers[rn], 1)
        end,

        [0xB] = function(rd, args)
            -- SHIFTR Rd, Rn
            local rn = args[2]
            Hardware.cpu.registers[rd] = bit.rshift(Hardware.cpu.registers[rn], 1)
        end,
    }


    cpu.clock = true

    function cpu.cycle(displayFunction)
        if not displayFunction then
            print("No display function provided, using default no-op.")
            displayFunction = function() end -- Default to a no-op if no display function is provided
        end
        cpu.clock = true
        if Hardware.bus.resetLine then
            displayFunction("Resetting CPU...")
            formatMem() -- Reset memory
            cpu.miscMemory.programCounter = 0x0000
            cpu.miscMemory.flagWasNegative = false
            cpu.miscMemory.flagWasZero = false
            cpu.miscMemory.shouldAdvancePC = true -- Reset the flag to allow PC to advance
            cpu.decoder.overflowRegister = 0x0000
            cpu.decoder.pendingFetch = false
            for i = 0, 15 do
                cpu.registers[i] = 0x0000 -- Reset all registers to zero
            end
            cpu.miscMemory.resetLine = false -- Reset the reset line
        end

        displayFunction("Top of cycle: Fetching...")

        -- Fetch
        Hardware.bus.writeLine = false -- Set the bus to read mode
        Hardware.bus.address = cpu.miscMemory.programCounter -- Set the address to the program counter
        Hardware.mem.read() -- Read the instruction from mem

        displayFunction("Fetched instructions: Decoding...")

        -- Decode
        cpu.decoder.decode()

        
        if not cpu.clock then
            -- If the clock is low, we need to wait for the next cycle as we have stalled
            displayFunction("Hanging in the decode phase, waiting for the next cycle...")
            return
        end
        
        displayFunction("Decoded instruction: Executing...")

        -- Execute
        local cb = cpu.decoder.contentBus
        local args = {}
        for i=0,5 do
            args[i+1] = bit.band(bit.rshift(cb, i*4), 0xF)
        end

        local opc = cpu.decoder.opcodeBus
        local rd  = cpu.decoder.destinationBus
        cpu.instructions[opc](rd, args)
        
        displayFunction("Executed instruction: beginning next cycle...")
        
        -- Increment the program counter
        if cpu.miscMemory.shouldAdvancePC then cpu.miscMemory.programCounter = cpu.miscMemory.programCounter + 1 end
        cpu.miscMemory.shouldAdvancePC = true -- Reset the flag for the next cycle

        cpu.clock = false -- Cycle the clock to false
    end

end

return Hardware
