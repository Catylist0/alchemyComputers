local Hardware = {}
local bit = require("bit")

Hardware.bus = {
    data = 0x0000, -- data bus
    address = 0x0000, -- address bus
    writeLine = false, -- boolean flag indicating if the bus is in a read cycle
    resetLine = false, -- boolean flag indicating if the reset line is active
    clock = true, -- boolean flag indicating if the clock is high
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
        if Hardware.bus.writeLine then return nil end -- If the bus is in a write cycle, do nothing
        local address = Hardware.bus.address
        local value = ram[address]
        Hardware.bus.data = value
    end

    function ram.write()
        if not Hardware.bus.writeLine then return nil end -- If the bus is not in a write cycle, do nothing
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
        opsWillOverflow = {},
        overflowRegister = 0x0000, -- holds the overflow value from the last operation if need be
        overflowFlag = false, -- boolean flag indicating if the last operation resulted in an overflow
        contentBus = 0x000000, -- sends the content of the instruction with an extremely short 24-bit bus
        destinationBus = 0x0, -- holds the destination register for the instruction with a 4-bit bus
        opcodeBus = 0x0, -- holds the opcode for the instruction with a 4-bit bus
        decode = function()
            -- decode the instruction from the first half of the word (the lower half of the word)
            --local data = Hardware.bus.data
            --cpu.decoder.opcodeBus = bit.band(data, 0xF0) -- first 4 bits are the opcode (total of 16 opcodes)
            --cpu.decoder.destinationBus = bit.band(data, 0x0F0) -- next 4 bits are the destination register (total of 16 registers)
            -- the content line are the remaining 8 bits, which are used for the operation
            --cpu.decoder.contentBus = bit.band(data, 0x00FF) -- last 8 bits

            local chunks = {bit.rshift(Hardware.bus.data, 12), bit.band(bit.rshift(Hardware.bus.data, 8), 0x0F), bit.band(bit.rshift(Hardware.bus.data, 4), 0x0F), bit.band(Hardware.bus.data, 0x0F)} -- split the 16-bit data into 4 4-bit chunks
            
            if cpu.decoder.opsWillOverflow[chunks[1]] and not cpu.decoder.overflowFlag then
                cpu.decoder.overflowFlag = true -- set the overflow flag if the operation will overflow
            end
            if not cpu.decoder.overFlowFlag then
                cpu.clock = false -- if the overflow flag is not set, then the clock is false to simulate a stall
            else
                -- all the chunks are sent to the overflow register
                cpu.decoder.overflowRegister = Hardware.bus.data
                cpu.decoder.opcodeBus = 0x0000 -- reset the overflow register
            end
        end,
        execute = function()
            operations[cpu.decoder.opcodeBus](cpu.decoder.destinationBus, cpu.decoder.contentBus)
        end
            
    }

    cpu.instructions = {}

    -- Define the instructions as they would be in the CPU
    local instructs = cpu.instructions

    --[[LOAD -- load an address to a register with an input register as an offset amount
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

    local clock = true

    function cpu.cycle()
        clock = true
        if hardware.bus.resetline then
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

        if not clock then
            -- If the clock is low, we need to wait for the next cycle as we have stalled
            return
        end

        -- Execute

        -- Read
        Hardware.ram.read()

        -- Increment the program counter
        cpu.miscMemory.programCounter = cpu.miscMemory.programCounter + 1

        clock = false -- Cycle the clock to simulate the low part of the clock cycle and simulate DDRAM access

        -- Write
        Hardware.ram.write()
    end

    Hardware.cpu = cpu
end

return Hardware