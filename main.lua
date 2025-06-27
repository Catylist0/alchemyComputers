local version = "0.0.1"
print("Starting...")
-- Set to true to run without terminal display
local headless = true
if DebugMode then
    headless = false
end
-- disabled garbage collection to try and fail to avoid performance issues
--collectgarbage("stop")
local term = require "term"
local Hardware = require "hardware"

local phaseHistory = {}
local hangTime = 0.1 -- seconds to hang after displaying each phase

local cycles = 0
local startTime = 0

require "ffilib" -- load the FFI library for sleep and time functions

local function emptyFunction(phase)
    -- This function is used when headless mode is enabled
    -- It does nothing but allows the CPU to cycle without displaying anything
end

local hertz = 0
local rollingHertz = 0
local resetTime = JIT_TIME()
local thisExecTime = 0
local thisDisplayTime = 0
local displayTimes = {}


-- Opcode values
local opcodes = {
    NOP    = 0x0,
    LOAD   = 0x1,
    STORE  = 0x2,
    ADDI   = 0x3,
    ADDR   = 0x4,
    SUBR   = 0x5,
    JMP    = 0x6,
    JMPZ   = 0x7,
    JMPN   = 0x8,
    NAND   = 0x9,
    SHIFTL = 0xA,
    SHIFTR = 0xB,
}

local opCodeToInstruction = {
    [0x0] = "NOP",
    [0x1] = "LOAD",
    [0x2] = "STORE",
    [0x3] = "ADDI",
    [0x4] = "ADDR",
    [0x5] = "SUBR",
    [0x6] = "JMP",
    [0x7] = "JMPZ",
    [0x8] = "JMPN",
    [0x9] = "NAND",
    [0xA] = "SHIFTL",
    [0xB] = "SHIFTR",
}

local function display(phase)
    local now = JIT_TIME()
    local uptime = now - resetTime

    local totalSleepTime = GET_TOTAL_SLEEP_TIME()
    local sleepTimeSinceLast = (totalSleepTime - (phaseHistory[2] and phaseHistory[2].sleepTimeSoFar or 0)) * 1000

    -- record this phase
    table.insert(phaseHistory, 1, {
        phase = phase,
        endTime = now,
        execTime = thisExecTime,
        sleepTimeSoFar = totalSleepTime,
        sleepTimeSinceLast = sleepTimeSinceLast,
        phaseTime = (thisExecTime - sleepTimeSinceLast) - (displayTimes[#displayTimes] or 0)
    })

    -- handle reset
    if phase == "Resetting CPU..." then
        cycles = 0
        resetTime = JIT_TIME()
    end

    -- recalc hertz on “Top of cycle” only
    if phase == "Top of cycle: Fetching..." then
        local sumExec = 0
        for i = 2, #phaseHistory do
            local entry = phaseHistory[i]
            if entry.phase == "Top of cycle: Fetching..." then
                break
            end
            local nextEnd = (i < #phaseHistory) and phaseHistory[i + 1].endTime or now
            local execSec = entry.endTime - nextEnd - hangTime
            if execSec > 0 then
                sumExec = sumExec + execSec
            end
        end
        hertz = (sumExec > 0) and (1 / sumExec) or 0
        -- rolling average of the last 10 hertz values
        rollingHertz = (hertz * 0.1) + (rollingHertz * 0.9)
    end

    -- render header
    term.wipe()
    term.line(term.center("ALC 1 INSTRUCTION SET CPU EMULATOR"))
    term.line(term.center("Version: " .. version))
    term.line(term.padLeft("CPU", 2) .. "Cycle: " .. cycles .. " | Uptime: " .. string.format("%.3f", uptime * 1000) ..
                  " ms" .. " | CPU Hertz: " .. string.format("%.2f", rollingHertz or 0) ..
                  " (" .. string.format("%.2f", hertz) .. ")")
    term.line("Phase: " .. phase)
    term.line("Clock: " .. tostring(Hardware.cpu.clock))
    term.line("")

    -- bus state
    term.line(term.padLeft("Bus", 2))
    term.line("Reset Line: " .. tostring(Hardware.bus.resetLine))
    term.line("Data Bus : 0x" .. string.format("%04X", Hardware.bus.data))
    term.line("Address  : 0x" .. string.format("%04X", Hardware.bus.address))
    term.line("Write Line: " .. tostring(Hardware.bus.writeLine))
    term.line("Clock Line: " .. tostring(Hardware.bus.clock))
    term.line("")

    -- registers
    term.line(term.padLeft("Registers", 2))
    for row = 0, 3 do
        local line = "  "
        for col = 0, 3 do
            local idx = row * 4 + col
            line = line .. string.format("r%X:0x%04X ", idx, Hardware.cpu.registers[idx])
        end
        term.line(line)
    end

    -- memory usage
    term.line("")
    term.line(term.padLeft("Memory", 2))
    term.line("RAM In use: " .. (Hardware.mem.addressesUsed * 2) .. " bytes")
    
    -- decoder state
    term.line("")
    term.line(term.padLeft("Decoder", 2))
    local decoder = Hardware.cpu.decoder
    term.line("Current Opcode: 0x" .. string.format("%X", decoder.opcodeBus) .. " (" .. opCodeToInstruction[decoder.opcodeBus] .. ")")
    -- destination is 4 nibbles, so we can display it as a hex value with 4 digits
    term.line("Current Destination: 0x" .. string.format("%01X", decoder.destinationBus))
    term.line("Current Rn: 0x" .. string.format("%X", decoder.rnBus)) 
    term.line("Current Rm: 0x" .. string.format("%X", decoder.rmBus))
    term.line("Content Bus: 0x" .. string.format("%04X", decoder.contentBus))
    term.line("Pending Fetch: " .. tostring(decoder.pendingFetch))

    -- misc CPU state
    term.line("")
    term.line(term.padLeft("Misc Memory", 2))
    local mm = Hardware.cpu.miscMemory
    term.line("PC           : 0x" .. string.format("%04X", mm.programCounter))
    local valueAtPC = Hardware.mem[mm.programCounter]
    if not valueAtPC then
        valueAtPC = 0
    end
    term.line("Memory At PC : 0x" .. string.format("%04X", valueAtPC))
    term.line("Flag Zero    : " .. tostring(mm.flagWasZero))
    term.line("Flag Negative: " .. tostring(mm.flagWasNegative))
    term.line("Advance PC   : " .. tostring(mm.shouldAdvancePC))
    term.line("")

    -- phase history log
    term.line(term.padLeft("Phase History", 2))
    local maxPhaseLen = 0
    for _, d in ipairs(phaseHistory) do
        if #d.phase > maxPhaseLen then
            maxPhaseLen = #d.phase
        end
    end
    for i, data in ipairs(phaseHistory) do
        if i > 10 then
            term.line("      ...")
            -- cull the remaining entries
            phaseHistory = {unpack(phaseHistory, 1, i)}
            break
        end
        local prefix = (i == 1) and "  --> " or "      "
        local nextTime = (i < #phaseHistory) and phaseHistory[i + 1].endTime or now
        local execMs = data.execTime
        local padded = data.phase .. string.rep(" ", maxPhaseLen - #data.phase)
        term.line(prefix .. padded .. " | Phase Time: " .. string.format("%.3f", data.phaseTime) ..
                      " ms | Sleep Time: " .. string.format("%.3f", data.sleepTimeSinceLast) ..
                      " ms | Exec Time: " .. string.format("%.3f", execMs) .. " ms | Display Time: " ..
                      string.format("%.3f", displayTimes[i] or 0) .. " ms")
    end

    term.render()

    thisDisplayTime = JIT_TIME() - now
    table.insert(displayTimes, thisDisplayTime)
end

local nextTime = 0

local function benchmarkedDisplay(phase)
    -- benchmark the display function and error out if it takes longer than 10ms to run
    local start = JIT_TIME()
    local ok, err = pcall(display, phase)
    if not ok then
        error("Display function failed: " .. tostring(err))
    end
    local elapsed = JIT_TIME() - start
    if elapsed > 0.05 then
        error(string.format("Display function took too long to execute: %.3f seconds", elapsed))
    end
    -- hang for a short time to simulate the CPU clock speed
    nextTime = nextTime + hangTime
    local now = JIT_TIME()
    local sleepTime = nextTime - now
    if sleepTime > 0 then
        SLEEP(sleepTime)
    else
        nextTime = now
    end

end

Hardware.bus.resetLine = true

local programStart = JIT_TIME()
cycles = 0

rollingHertz = 0

local ok, err = pcall(function()
    print("Starting CPU cycles...")
    while true do
        startTime = JIT_TIME()
        if headless then
            Hardware.cpu.cycle(emptyFunction)
        else
            thisExecTime = (JIT_TIME() - startTime) * 1000 -- in milliseconds
            rollingHertz = (rollingHertz * 0.95) + (1 / thisExecTime * 0.05) -- rolling average
            Hardware.cpu.cycle(benchmarkedDisplay)
        end
        cycles = cycles + 1
        if cycles % 100 == 0 and headless then
            local now = JIT_TIME()
            local uptime = now - programStart
            term.line(string.format("Cycles: %d | Uptime: %.3f ms | CPU Hertz: %.2f (rolling: %.2f)", 
                cycles, uptime * 1000, (cycles / uptime), rollingHertz))
            term.render()
        end
    end
end)

print("An error occurred during execution...")

if not ok then
    print("An error occurred during execution...")
    local crashTime = JIT_TIME()
    local uptime = crashTime - programStart
    term.printBenchmarks()
    print(string.format("Benchmark aborted after %.3f seconds (%d cycles executed).", uptime, cycles))
    print(string.format("Uptime: %.3f ms.", uptime * 1000))
    local hertz = (uptime > 0) and (cycles / uptime) or 0
    -- print hertz and rolling hertz
    print(string.format("CPU Hertz: %.2f (rolling: %.2f)", hertz, rollingHertz))
    print("Error: " .. err)
    -- print callstack
    local traceback = debug.traceback()
    print(traceback)
end
