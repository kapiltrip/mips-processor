`timescale 1ns/1ps
module alu(
    input  wire [5:0]  opcode,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
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
               BEQZ  = 6'b010000;

    always @* begin
        case (opcode)
            ADD, ADDI, LW, SW, BNEQZ, BEQZ: result = a + b;
            SUB, SUBI:                      result = a - b;
            AND:                            result = a & b;
            OR:                             result = a | b;
            SLT, SLTI:                      result = (a < b) ? 32'd1 : 32'd0;
            MUL:                            result = a * b;
            default:                        result = 32'hxxxxxxxx;
        endcase
    end
endmodule
