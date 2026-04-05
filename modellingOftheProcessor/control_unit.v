`timescale 1ns/1ps
module control_unit(
    input  wire [5:0] opcode,
    output reg  [2:0] instr_type
);
    // Opcodes
    localparam ADD   = 6'b000000,
               SUB   = 6'b000001,
               AND   = 6'b000010,
               SLT   = 6'b000011,
               MUL   = 6'b000100,
               OR    = 6'b000101,
               ADDI  = 6'b001010,
               SUBI  = 6'b001011,
               SLTI  = 6'b001100,
               LW    = 6'b001101,
               SW    = 6'b001110,
               BNEQZ = 6'b001111,
               BEQZ  = 6'b010000,
               HLT   = 6'b111111;

    // Instruction type tags
    localparam RR_ALU = 3'b000,
               RM_ALU = 3'b001,
               LOAD   = 3'b010,
               STORE  = 3'b011,
               BRANCH = 3'b100,
               HALT   = 3'b101;

    always @* begin
        case (opcode)
            ADD, SUB, AND, OR, SLT, MUL: instr_type = RR_ALU;
            ADDI, SUBI, SLTI:            instr_type = RM_ALU;
            LW:                          instr_type = LOAD;
            SW:                          instr_type = STORE;
            BNEQZ, BEQZ:                 instr_type = BRANCH;
            HLT:                         instr_type = HALT;
            default:                     instr_type = HALT;
        endcase
    end
endmodule
