local OPCODES = {
    NOP = 0x00,
    SET = 0x01,
    LOAD = 0x02,
    STORE = 0x03,
    ADD = 0x04,
    SUB = 0x05,
    MUL = 0x06,
    DIV = 0x07,
    AND = 0x08,
    OR = 0x09,
    XOR = 0x0A,
    NOT = 0x0B,
    JMP = 0x0C,
    JZ = 0x0D,
    JNZ = 0x0E,
    HALT = 0x0F
}

local function encode(string)
    -- split string into lines, then into space-separated tokens
    local lines = {}
    for line in string:gmatch("[^\r\n]+") do
        -- check that the first token is a valid opcode
        local tokens = {}
        for token in line:gmatch("%S+") do
            table.insert(tokens, token)
        end
        table.insert(lines, tokens)
    end
end