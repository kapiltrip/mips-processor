`timescale 1ns/1ps
module memory_interface(
    input  wire        clock,
    input  wire [31:0] instr_addr,
    output wire [31:0] instr_out,
    input  wire [31:0] data_addr,
    input  wire [31:0] data_in,
    output wire [31:0] data_out,
    input  wire        data_we
);
    reg [31:0] mem[0:1023];

    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            mem[i] = 32'd0;
        end
    end

    assign instr_out = mem[instr_addr];
    assign data_out  = mem[data_addr];

    always @(posedge clock) begin
        if (data_we) begin
            mem[data_addr] <= data_in;
        end
    end
endmodule
