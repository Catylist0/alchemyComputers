local term = require "term"
encodingParadigm = {}

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

encodingParadigm.instructions = {}