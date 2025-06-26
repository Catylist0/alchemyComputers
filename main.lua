local version = "0.0.1"

local function getTerminalSize()
    local handle = io.popen("stty size", "r")
    local output = handle:read("*l")
    handle:close()
    local r, c = output:match("^(%d+)%s+(%d+)$")
    return tonumber(r), tonumber(c)
end

local rows, cols = getTerminalSize()

-- Clear screen and move cursor to bottom-left
io.write("\27[2J", string.format("\27[%d;1H", rows))

local Hardware = require "hardware"
local buf = {}

local function renderLine(n, txt)
    buf[n] = txt
end

local function flush()
    io.write("\27[2J")
    for i = 1, rows do
        io.write(("\27[%d;1H%s"):format(i, buf[i] or ""))
    end
    io.write(("\27[%d;1H"):format(rows))
end

local phaseHistory = {}

local function displayFunction(phase)
    rows, cols = getTerminalSize()
    table.insert(phaseHistory, phase)
    buf = {}

    -- Header
    renderLine(1, "Hardware Emulator Version " .. version)
    renderLine(2, "Phase: " .. phase)

    -- Registers
    renderLine(3, "Registers:")
    do
        local rn = 0
        for row = 1, 4 do
            local colsTbl = {}
            for col = 1, 4 do
                colsTbl[#colsTbl + 1] = ("R%02X:0x%04X"):format(rn, Hardware.cpu.registers[rn] or 0)
                rn = rn + 1
            end
            renderLine(3 + row, table.concat(colsTbl, " | "))
        end
    end

    -- Buses
    renderLine(8, "Buses:")
    renderLine(9, ("Address:       0x%04X"):format(Hardware.bus.address or 0))
    renderLine(10, ("Data:          0x%04X"):format(Hardware.bus.data or 0))
    renderLine(11, "Write Line:    " .. tostring(Hardware.bus.writeLine))
    renderLine(12, "Reset Line:    " .. tostring(Hardware.bus.resetLine))
    renderLine(13, "Clock Line:    " .. tostring(Hardware.bus.clock))

    -- Misc Memory
    renderLine(15, "Misc Memory:")
    renderLine(16, ("PC:            0x%04X"):format(Hardware.cpu.miscMemory.programCounter or 0))
    renderLine(17, "Flag Zero:     " .. tostring(Hardware.cpu.miscMemory.flagWasZero))
    renderLine(18, "Flag Negative: " .. tostring(Hardware.cpu.miscMemory.flagWasNegative))
    renderLine(19, "Advance PC?:   " .. tostring(Hardware.cpu.miscMemory.shouldAdvancePC))

    -- Decoder
    renderLine(21, "Decoder:")
    renderLine(22, "PendingFetch:  " .. tostring(Hardware.cpu.decoder.pendingFetch))
    renderLine(23, ("OverflowReg:   0x%04X"):format(Hardware.cpu.decoder.overflowRegister or 0))
    renderLine(24, ("OpcodeBus:     0x%X"):format(Hardware.cpu.decoder.opcodeBus or 0))
    renderLine(25, ("DestBus:       0x%X"):format(Hardware.cpu.decoder.destinationBus or 0))
    renderLine(26, ("ContentBus:    0x%06X"):format(Hardware.cpu.decoder.contentBus or 0))

    -- History
    renderLine(28, "History:")
    local historyStart = 29
    for i = 1, #phaseHistory do
        if historyStart + i - 1 <= rows then
            renderLine(historyStart + i - 1, phaseHistory[i])
        end
    end

    flush()
    os.execute("sleep 1")
end

Hardware.bus.resetLine = true

while true do
    Hardware.cpu.cycle(displayFunction)
end
