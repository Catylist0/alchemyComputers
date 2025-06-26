local Hardware = {}
local bit = require("bit")

Hardware.bus = {
    data = 0x0000, -- data bus
    address = 0x0000, -- address bus
    writeLine = false, -- boolean flag indicating if the bus is in a read cycle
    resetLine = false, -- boolean flag indicating if the reset line is active
    clock = true -- boolean flag indicating if the clock is high
}

Hardware.ram = {}
Hardware.rom = {}

function formatRam()
    for i = 0, 0xFFFF do
        Hardware.ram[i] = 0x0000 -- Initialize RAM with zeroes
    end
end

do
    local ram = Hardware.ram

    function ram.read()
        if Hardware.bus.writeLine then
            return nil
        end -- If the bus is in a write cycle, do nothing
        local address = Hardware.bus.address
        local value = ram[address]
        Hardware.bus.data = value
    end

    function ram.write()
        if not Hardware.bus.writeLine then
            return nil
        end -- If the bus is not in a write cycle, do nothing
        local address = Hardware.bus.address
        local value = Hardware.bus.data
        ram[address] = value
    end
end

Hardware.cpu = {}
do
    local cpu = Hardware.cpu

    cpu.miscMemory = {
        programCounter = 0x0000, -- holds the address of the next instruction to execute
        flagWasNegative = false, -- boolean flag indicating if the last instruction resulted in a negative value
        flagWasZero = false -- boolean flag indicating if the last instruction resulted in a zero value
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
            [0x1] = true,  -- LOAD   (24-bit)
            [0x2] = true,  -- STORE  (24-bit)
            [0x3] = true,  -- ADDI   (28-bit)
            [0x6] = true,  -- JMP    (20-bit)
            [0x7] = true,  -- JMPZ   (20-bit)
            [0x8] = true,  -- JMPN   (20-bit)
        },
        pendingFetch   = false,
        overflowRegister = 0x0000,  -- holds entire first 16-bit fetch
        opcodeBus      = 0x0,
        destinationBus = 0x0,
        contentBus     = 0x000000,

        decode = function()
            local raw = Hardware.bus.data  -- first 16 bits

            if not cpu.decoder.pendingFetch then
                local top  = bit.rshift(raw, 12)
                local dest = bit.band(bit.rshift(raw, 8), 0xF)

                cpu.decoder.opcodeBus      = top
                cpu.decoder.destinationBus = dest

                if cpu.decoder.twoCycleOpcodes[top] then
                    cpu.decoder.pendingFetch   = true
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
            local low   = bit.band(first, 0xFF)

            cpu.decoder.opcodeBus      = bit.rshift(first, 12)
            cpu.decoder.destinationBus = bit.band(bit.rshift(first, 8), 0xF)
            cpu.decoder.contentBus     = bit.bor(bit.lshift(low, 16), bit.band(ext, 0xFFFF))

            cpu.decoder.pendingFetch = false
        end
    }

    cpu.instructions = {
        [0x0] = function() end,    -- NOP

        [0x1] = function(rd, addr) -- LOAD  Rd, addr
            Hardware.bus.writeLine = false -- Set the bus to read mode
            Hardware.bus.address = addr -- Set the address to the given address
            Hardware.ram.read()
            Hardware.cpu.registers[rd] = Hardware.bus.data -- Direct the data from the bus into the register
            Hardware.bus.data = 0x0000 -- Clear the bus data
            Hardware.bus.address = 0x0000 -- Clear the bus address
        end,

        [0x2] = function(rd, addr) -- STORE Rd, addr
            Hardware.bus.writeLine = true -- Set the bus to write mode
            Hardware.bus.address = addr -- Set the address to the given address
            Hardware.bus.data = Hardware.cpu.registers[rd] -- Set the data to the value
            Hardware.ram.write() -- Write the data to RAM
            Hardware.bus.writeLine = false -- Reset the bus to read mode
            Hardware.bus.data = 0x0000 -- Clear the bus data
            Hardware.bus.address = 0x0000 -- Clear the bus address
        end,

        [0x3] = function(rd, rn, imm) -- ADDI Rd, Rn, Imm
            Hardware.cpu.registers[rd] = Hardware.cpu.registers[rn] + imm
        end,

        [0x4] = function(rd, rn, rm) -- ADDR Rd, Rn, Rm
            Hardware.cpu.registers[rd] = Hardware.cpu.registers[rn] + Hardware.cpu.registers[rm]
        end,

        [0x5] = function(rd, rn, rm) -- SUBR Rd, Rn, Rm
            local result = Hardware.cpu.registers[rn] - Hardware.cpu.registers[rm]
            Hardware.cpu.miscMemory.flagWasZero     = (result == 0)
            Hardware.cpu.miscMemory.flagWasNegative = (result < 0)
            Hardware.cpu.registers[rd]              = result
        end,

        [0x6] = function(addr) -- JMP, addr
            Hardware.cpu.miscMemory.programCounter = addr
            Hardware.cpu.registers[1] = addr
        end,

        [0x7] = function(addr) -- JMPZ [link?], addr
            if Hardware.cpu.miscMemory.flagWasZero then
                Hardware.cpu.miscMemory.programCounter = addr
            end
        end,

        [0x8] = function(addr) -- JMPN [link?], addr
            if Hardware.cpu.miscMemory.flagWasNegative then
                Hardware.cpu.miscMemory.programCounter = addr
            end
        end,

        [0x9] = function(rd, rn, rm) -- NAND Rd, Rn, Rm
            local result = bit.bnot(bit.band(
                Hardware.cpu.registers[rn],
                Hardware.cpu.registers[rm]
            ))
            Hardware.cpu.registers[rd] = result
        end,

        [0xA] = function(rd, rn) -- SHIFTL Rd, Rn
            Hardware.cpu.registers[rd] = bit.lshift(Hardware.cpu.registers[rn], 1)
        end,

        [0xB] = function(rd, rn) -- SHIFTR Rd, Rn
            Hardware.cpu.registers[rd] = bit.rshift(Hardware.cpu.registers[rn], 1)
        end,
    }



    --[[
        The instruction set is as follows:
        NOP -- no operation, does nothing
        LOAD -- load an address to a register with an input register as an offset amount
        STORE -- store a register to an address with an input register as an offset amount
        ADDI -- add an immediate number to a register
        ADDR -- add a register to another register
        SUBR -- subtract a register from another register and sets the Was Result Zero flag as well as the negative flag.
        JMP -- unconditional jump to an address, also writes the address to the link register if the link arg is set.
        JMPZ -- conditional jump, jumps to an address if the previous operation's result was 0 using a arg, also writes the 
                address to the link register if the link flag is set.
        JMPN -- conditional jump, jumps to an address if the previous operation's result was 
                negative using the Was Result Negative flag, also writes the address to the link register if the link arg is set.
        NAND -- bitwise NAND operator 
        SHIFTL -- bitwise shift left operator (doubling)
        SHIFTR -- bitwise shift right operator (halving)

        Syntax and instruction smallest possible size:
        NOP (0 bits)
        LOAD Rd <address> (24 bits)
        STORE Rd <address> (24 bits)
        ADDI Rd Rn Imm (28 bits)
        ADDR Rd Rn Rm (16 bits)
        SUBR Rd Rn Rm (16 bits)
        JMP <address> (20 bits)
        JMPZ <address> (20 bits)
        JMPN <address> (20 bits)
        NAND Rd Rn Rm (16 bits)
        SHIFTL Rd Rn (12 bits)
        SHIFTR Rd Rn (12 bits)

        Bytecode is fetched in 16 bit chunks, the decoder knows if it needs to wait for the next chunk 
        before executing by analyzing the instruction codes and stalling out the cycle.
        ]]

    cpu.clock = true

    function cpu.cycle()
        cpu.clock = true
        if Hardware.bus.resetLine then
            cpu.miscMemory.programCounter = 0x0000
            cpu.miscMemory.flagWasNegative = false
            cpu.miscMemory.flagWasZero = false
            cpu.decoder.overflowRegister = 0x0000
            cpu.decoder.overflowFlag = false
        end

        -- Fetch
        bus.writeLine = false -- Set the bus to read mode
        Hardware.bus.address = cpu.miscMemory.programCounter -- Set the address to the program counter
        Hardware.ram.read() -- Read the instruction from RAM

        -- Decode
        cpu.decoder.decode()

        if not cpu.clock then
            -- If the clock is low, we need to wait for the next cycle as we have stalled
            return
        end

        -- Execute

        -- split the 24 bit content bus into 4 bit chunks
        local executionChunks = {}
        for i = 1, 5 do -- ignore the first 4 bits as they are the opcode
            local chunk = bit.band(bit.rshift(cpu.decoder.contentBus, i * 4), 0xF)
            executionChunks[i+1] = chunk
        end
        local opcode = cpu.decoder.opcodeBus
        local destination = cpu.decoder.destinationBus
        cpu.instructions[opcode](destination, executionChunks)

        -- Increment the program counter
        cpu.miscMemory.programCounter = cpu.miscMemory.programCounter + 1

        cpu.clock = false -- Cycle the clock to false
    end

end

return Hardware
