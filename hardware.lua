local Hardware = {}
local bit = require("bit")

-- load the tape.txt file
local tapeFile = "storage.txt"
local tapeHandle = io.open(tapeFile, "r")
if not tapeHandle then
    error("Could not open tape file: " .. tapeFile)
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
    local romSrc = "assemblerOutput/rom.hex"
    local romFile = assert(io.open(romSrc, "r"), "Could not open ROM file")
    for addr = 0, 0xFF do
        local line = romFile:read("*l")
        if not line then break end        -- stop if fewer than 256 lines
        -- strip any leading/trailing whitespace
        line = line:match("^%s*(.-)%s*$")
        -- parse "0xWWWW" into a number
        local value = tonumber(line, 16)
        assert(value, "Invalid hex on line "..addr)
        Hardware.mem[addr] = value
    end
    romFile:close()
    for i = 0x0100, 0xFFFF do
        Hardware.mem[i] = 0x0000
    end
    Hardware.mem[0x0000] = 0x0000
end

local ramUseMatrix = {}
Hardware.mem.addressesUsed = 0x0000

do
    formatMem() -- Initialize memory
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
        if Hardware.bus.writeLine then return end
        local address = Hardware.bus.address
        local space   = returnAddressSpace(address)
        local value
        if space == "ROM" or space == "RAM" then
            value = mem[address]
        elseif space == "MAG" then
            -- TODO: read tape into `value`
        else
            value = 0  -- fallback so bus.data is never left nil
        end
        Hardware.bus.data = value or 0
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
    -- register 0x0 is the zero register, always 0x0000
    -- register 0x1 is the link register

    -- Updated decoder:
    cpu.decoder = {
        twoCycleOpcodes = { [0x1]=true, [0x2]=true, [0x3]=true },
        pendingFetch    = false,
        opcodeBus       = 0x0,
        destinationBus  = 0x0,
        rnBus           = 0x0,
        rmBus           = 0x0,
        contentBus      = 0x0000,

        decode = function()
            local raw = Hardware.bus.data

            if not cpu.decoder.pendingFetch then
                -- Phase 1: extract fields from W1
                local op = bit.rshift(raw, 12)
                local rd = bit.band(bit.rshift(raw,  8), 0xF)
                local rn = bit.band(bit.rshift(raw,  4), 0xF)
                local rm = bit.band(raw,               0xF)

                cpu.decoder.opcodeBus      = op
                cpu.decoder.destinationBus = rd
                cpu.decoder.rnBus          = rn
                cpu.decoder.rmBus          = rm

                if cpu.decoder.twoCycleOpcodes[op] then
                    -- stall to fetch W2
                    cpu.decoder.pendingFetch = true
                    cpu.clock = false
                    return
                end

                -- single-cycle: no W2, so contentBus = 0
                cpu.decoder.contentBus = 0x0000
                return
            end

            -- Phase 2: second word arrived, that is the 16-bit payload
            cpu.decoder.contentBus   = bit.band(Hardware.bus.data, 0xFFFF)
            cpu.decoder.pendingFetch = false
        end,

        execute = function()
            local op      = cpu.decoder.opcodeBus
            local rd      = cpu.decoder.destinationBus
            local rn      = cpu.decoder.rnBus
            local rm      = cpu.decoder.rmBus
            local payload = cpu.decoder.contentBus

            -- assert all of these are valid and the correct length
            assert(type(op) == "number" and op >= 0 and op <= 0xF, "Opcode must be a number between 0 and 15")
            assert(type(rd) == "number" and rd >= 0 and rd <= 0xF, "Destination register must be a number between 0 and 15")
            assert(type(rn) == "number" and rn >= 0 and rn <= 0xF, "Rn register must be a number between 0 and 15")
            assert(type(rm) == "number" and rm >= 0 and rm <= 0xF, "Rm register must be a number between 0 and 15")
            assert(type(payload) == "number" and payload >= 0 and payload <= 0xFFFF, "Payload must be a number between 0 and 65535")

            cpu.instructions[op](rd, rn, rm, payload)
        end,
    }

    -- Updated instruction implementations:
    cpu.instructions = {
        [0x0] = function(rd, rn, rm, payload) 
            -- NOP
        end,

        [0x1] = function(rd, rn, rm, payload)  -- LOAD
            Hardware.bus.writeLine = false
            Hardware.bus.address   = payload
            Hardware.mem.read()
            cpu.registers[rd]      = Hardware.bus.data
            Hardware.bus.address   = 0
        end,

        [0x2] = function(rd, rn, rm, payload)  -- STORE
            Hardware.bus.writeLine = true
            Hardware.bus.address   = payload
            Hardware.bus.data      = cpu.registers[rd]
            Hardware.mem.write()
            Hardware.bus.writeLine = false
            Hardware.bus.data      = 0
            Hardware.bus.address   = 0
        end,

        [0x3] = function(rd, rn, rm, payload)  -- ADDI
            -- ADDI is an immediate addition, where payload is a 16-bit value
            cpu.registers[rd] = cpu.registers[rn] + payload
        end,

        [0x4] = function(rd, rn, rm, payload)  -- ADDR
            cpu.registers[rd] = cpu.registers[rn] + cpu.registers[rm]
        end,

        [0x5] = function(rd, rn, rm, payload)  -- SUBR
            local res = cpu.registers[rn] - cpu.registers[rm]
            cpu.miscMemory.flagWasZero     = (res == 0)
            cpu.miscMemory.flagWasNegative = (res < 0)
            cpu.registers[rd]              = res
        end,

        [0x6] = function(rd, rn, rm, payload)  -- JMP
            cpu.miscMemory.shouldAdvancePC = false
            cpu.miscMemory.programCounter  = cpu.registers[rd]
            cpu.registers[0x1]             = cpu.registers[rd]  -- link register
        end,

        [0x7] = function(rd, rn, rm, payload)  -- JMPZ
            if cpu.miscMemory.flagWasZero then
                cpu.miscMemory.shouldAdvancePC = false
                cpu.miscMemory.programCounter  = cpu.registers[rd]
            end
        end,

        [0x8] = function(rd, rn, rm, payload)  -- JMPN
            if cpu.miscMemory.flagWasNegative then
                cpu.miscMemory.shouldAdvancePC = false
                cpu.miscMemory.programCounter  = cpu.registers[rd] -- set the program counter to the value in rd
            end
        end,

        [0x9] = function(rd, rn, rm, payload)  -- NAND
            cpu.registers[rd] = bit.bnot(
                bit.band(cpu.registers[rn], cpu.registers[rm])
            )
        end,

        [0xA] = function(rd, rn, rm, payload)  -- SHIFTL
            cpu.registers[rd] = bit.lshift(cpu.registers[rn], 1)
        end,

        [0xB] = function(rd, rn, rm, payload)  -- SHIFTR
            cpu.registers[rd] = bit.rshift(cpu.registers[rn], 1)
        end,
    }

    cpu.clock = true

    function cpu.cycle(displayFunction)
        cpu.miscMemory.shouldAdvancePC = true
        --os.exit(0) -- exit ripple if this is uncommented - will not launch again until commented out
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
        
        if cpu.miscMemory.shouldAdvancePC then
            cpu.miscMemory.programCounter = cpu.miscMemory.programCounter + 1
        end

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

        cpu.decoder.execute()
        cpu.clock = false
    end
end

return Hardware
