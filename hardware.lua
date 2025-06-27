local Hardware = {}
local bit = require("bit")

-- load the tape.txt file
local tapeFile = "tape.txt"
local tapeHandle = io.open(tapeFile, "r")
if not tapeHandle then
    error("Could not open tape file: " .. tapeFile)
end
for address, value in tapeHandle:lines() do
    Hardware.mem[address] = value
end
tapeHandle:close()

-- Cross-platform file mtime check (replaces lfs)
local function get_mtime(file)
    if jit.os == "Windows" then
        local cmd = 'powershell -Command "(Get-Item \'' .. file .. '\').LastWriteTimeUtc.ToFileTimeUtc()"'
        local handle = io.popen(cmd)
        if not handle then return nil end
        local output = handle:read("*a")
        handle:close()
        local fileTime = tonumber(output)
        if not fileTime then return nil end
        return fileTime / 10000000 - 11644473600
    else
        local handle = io.popen("stat -c %Y " .. file)
        if not handle then return nil end
        local result = handle:read("*a")
        handle:close()
        return tonumber(result)
    end
end

Hardware.bus = {
    data = 0x0000,
    address = 0x0000,
    writeLine = false,
    resetLine = false,
    clock = true,
}

Hardware.mem = {}

local function formatMem()
    for i = 0, 0xFF do 
        Hardware.mem[i] = 0x0000
    end
    for i = 0x0100, 0xFFFF do
        Hardware.mem[i] = 0x0000
    end
    Hardware.mem[0x0000] = 0x0000
end

local ramUseMatrix = {}
Hardware.mem.addressesUsed = 0x0000

do
    local mem = Hardware.mem

    mem.addressSpace = {
        [0x0000] = "ROM",
        [0x0100] = "MAG", -- When loaded or written to, will forward to the tape head and advance the storage tape
        [0x0101] = "PERIPHERAL", -- each peripheral knows when it is read or written to and has a behavior hooked in, disk drives work like the magnetic tape, advancing when read or written.
        [0x0110] = "RAM",
    }

    local function returnAddressSpace(address)
        for k, v in pairs(mem.addressSpace) do
            if address >= k then
                return v
            end
        end
        return "NIL"
    end

    function mem.read()
        if Hardware.bus.writeLine then return nil end
        local address = Hardware.bus.address
        local addressSpace = returnAddressSpace(address)
        if addressSpace == "ROM" then
            local value = mem[address]
            Hardware.bus.data = value
        elseif addressSpace == "RAM" then
            local value = mem[address]
            Hardware.bus.data = value
        elseif addressSpace == "MAG" then
            -- Handle magnetic tape read
            --mem.magtape 
        end
    end

    function mem.write()
        if not Hardware.bus.writeLine then return nil end
        local address = Hardware.bus.address
        local value = Hardware.bus.data
        mem[address] = value
        if not release then
            if not ramUseMatrix[address] then
                ramUseMatrix[address] = true 
                Hardware.mem.addressesUsed = Hardware.mem.addressesUsed + 1
            end
        else
            ramUseMatrix[address] = nil
            Hardware.mem.addressesUsed = Hardware.mem.addressesUsed - 1
        end
    end
end

Hardware.cpu = {}
do
    local cpu = Hardware.cpu

    cpu.miscMemory = {
        programCounter = 0x0000,
        flagWasNegative = false,
        flagWasZero = false,
        shouldAdvancePC = false
    }

    cpu.registers = {}
    for i = 0, 0xF do cpu.registers[i] = 0x0000 end

    cpu.decoder = {
        twoCycleOpcodes = {
            [0x1] = true, [0x2] = true, [0x3] = true,
            [0x6] = true, [0x7] = true, [0x8] = true
        },
        pendingFetch = false,
        overflowRegister = 0x0000,
        opcodeBus = 0x0,
        destinationBus = 0x0,
        contentBus = 0x000000,

        decode = function()
            local raw = Hardware.bus.data
            if not cpu.decoder.pendingFetch then
                local top = bit.rshift(raw, 12)
                local dest = bit.band(bit.rshift(raw, 8), 0xF)
                cpu.decoder.opcodeBus = top
                cpu.decoder.destinationBus = dest
                if cpu.decoder.twoCycleOpcodes[top] then -- if this is a two-cycle opcode -> then we want to populate the overflow register with the raw data
                    -- Case: two-cycle opcode, we need to wait for the next cycle to fetch the rest of the data so we populate the overflow register
                    cpu.decoder.pendingFetch = true
                    cpu.decoder.overflowRegister = raw
                    cpu.clock = false
                    return
                end
                -- Case: single-cycle opcode with no overflow in the register
                cpu.decoder.contentBus = 0x000000 -- reset content bus
                cpu.decoder.contentBus = bit.band(raw, 0xFFFF) -- drop the 16bit overflow into the lower half of the content bus
                return
            end
            -- Case: two-cycle opcode, and the overflow register is populated, so we know we can go ahead and decode the instruction
            cpu.decoder.contentBus = 0x000000 -- reset content bus
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
        [0x0] = function(rd, args) end,

        [0x1] = function(rd, args)
            local addr = combineNibbles(args, 1, 6)
            Hardware.bus.writeLine = false
            Hardware.bus.address = addr
            Hardware.mem.read()
            Hardware.cpu.registers[rd] = Hardware.bus.data
            Hardware.bus.data = 0
            Hardware.bus.address = 0
        end,

        [0x2] = function(rd, args)
            local addr = combineNibbles(args, 1, 6)
            Hardware.bus.writeLine = true
            Hardware.bus.address = addr
            Hardware.bus.data = Hardware.cpu.registers[rd]
            Hardware.mem.write()
            Hardware.bus.writeLine = false
            Hardware.bus.data = 0
            Hardware.bus.address = 0
        end,

        [0x3] = function(rd, args)
            local rn = args[1]
            local imm = combineNibbles(args, 2, 5)
            Hardware.cpu.registers[rd] = Hardware.cpu.registers[rn] + imm
        end,

        [0x4] = function(rd, args)
            local rn = args[2]
            local rm = args[1]
            Hardware.cpu.registers[rd] = Hardware.cpu.registers[rn] + Hardware.cpu.registers[rm]
        end,

        [0x5] = function(rd, args)
            local rn = args[2]
            local rm = args[1]
            local res = Hardware.cpu.registers[rn] - Hardware.cpu.registers[rm]
            cpu.miscMemory.flagWasZero = (res == 0)
            cpu.miscMemory.flagWasNegative = (res < 0)
            Hardware.cpu.registers[rd] = res
        end,

        [0x6] = function(_, args)
            cpu.miscMemory.shouldAdvancePC = false
            local addr = combineNibbles(args, 1, 5)
            cpu.miscMemory.programCounter = addr
            Hardware.cpu.registers[0x1] = addr
        end,

        [0x7] = function(_, args)
            cpu.miscMemory.shouldAdvancePC = false
            local addr = combineNibbles(args, 1, 5)
            if cpu.miscMemory.flagWasZero then
                cpu.miscMemory.programCounter = addr
            end
        end,

        [0x8] = function(_, args)
            cpu.miscMemory.shouldAdvancePC = false
            local addr = combineNibbles(args, 1, 5)
            if cpu.miscMemory.flagWasNegative then
                cpu.miscMemory.programCounter = addr
            end
        end,

        [0x9] = function(rd, args)
            local rn = args[2]
            local rm = args[1]
            Hardware.cpu.registers[rd] =
                bit.bnot(bit.band(Hardware.cpu.registers[rn], Hardware.cpu.registers[rm]))
        end,

        [0xA] = function(rd, args)
            local rn = args[2]
            Hardware.cpu.registers[rd] = bit.lshift(Hardware.cpu.registers[rn], 1)
        end,

        [0xB] = function(rd, args)
            local rn = args[2]
            Hardware.cpu.registers[rd] = bit.rshift(Hardware.cpu.registers[rn], 1)
        end
    }

    cpu.clock = true

    function cpu.cycle(displayFunction)
        --os.exit(0) -- ensure we are running in a luajit instance
        local filesToCheck = {
            "hardware.lua",
            "main.lua",
            "debug.lua",
            "term.lua"
        }
        for _, file in ipairs(filesToCheck) do
            local mtime = get_mtime(file)
            if mtime and os.time() - mtime < 1 then
                displayFunction("Detected changes in " .. file .. ", restarting the luajit instance...")
                -- start a new luajit instance of this software and block the thread with It
                local file = "debug.lua"
                os.execute("luajit " .. file)
                os.exit(0)
            end
        end

        assert(type(displayFunction) == "function", "Display function must be a function")

        cpu.clock = true

        if Hardware.bus.resetLine then
            displayFunction("Resetting CPU...")
            formatMem()
            cpu.miscMemory.programCounter = 0x0000
            cpu.miscMemory.flagWasNegative = false
            cpu.miscMemory.flagWasZero = false
            cpu.miscMemory.shouldAdvancePC = true
            cpu.decoder.overflowRegister = 0x0000
            cpu.decoder.pendingFetch = false
            for i = 0, 15 do
                cpu.registers[i] = 0x0000
            end
            Hardware.bus.resetLine = false
        end

        displayFunction("Top of cycle: Fetching...")
        Hardware.bus.writeLine = false
        Hardware.bus.address = cpu.miscMemory.programCounter
        Hardware.mem.read()

        displayFunction("Fetched instructions: Decoding...")
        cpu.decoder.decode()

        if not cpu.clock then
            displayFunction("Hanging in the decode for next cycle...")
            return
        end

        displayFunction("Decoded instruction: Executing...")
        local cb = cpu.decoder.contentBus
        local args = {}
        for i = 0, 5 do
            args[i+1] = bit.band(bit.rshift(cb, i*4), 0xF) -- pull out nibbles (4 bits 16 decimal each)
        end

        local opc = cpu.decoder.opcodeBus
        local rd  = cpu.decoder.destinationBus
        cpu.instructions[opc](rd, args)

        displayFunction("Instruction Executed: Incrementing Program Counter...")
        if cpu.miscMemory.shouldAdvancePC then
            cpu.miscMemory.programCounter = cpu.miscMemory.programCounter + 1
        end
        cpu.miscMemory.shouldAdvancePC = true
        cpu.clock = false
    end
end

return Hardware
