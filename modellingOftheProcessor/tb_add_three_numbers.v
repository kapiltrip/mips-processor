`timescale 1ns/1ps

module tb_add_three_numbers;
    reg clock1, clock2;
    integer k;

    mips uut(.clock1(clock1), .clock2(clock2));

    initial begin
        clock1 = 0;
        clock2 = 0;

        // Initialize register file for visibility.
        for (k = 0; k < 32; k = k + 1)
            uut.rf.regs[k] = k;

        // Program: add 10, 20, and 25. Final sum should be in R5.
        uut.memory.mem[0] = 32'h2801000a; // ADDI R1, R0, 10
        uut.memory.mem[1] = 32'h28020014; // ADDI R2, R0, 20
        uut.memory.mem[2] = 32'h28030019; // ADDI R3, R0, 25
        uut.memory.mem[3] = 32'h14e73800; // OR R7, R7, R7
        uut.memory.mem[4] = 32'h14e73800; // OR R7, R7, R7
        uut.memory.mem[5] = 32'h00222000; // ADD R4, R1, R2
        uut.memory.mem[6] = 32'h14e73800; // OR R7, R7, R7
        uut.memory.mem[7] = 32'h00832800; // ADD R5, R4, R3
        uut.memory.mem[8] = 32'hfc000000; // HLT

        uut.PC = 0;
        uut.halted = 0;
        uut.taken_branch = 0;

        // Initialize pipeline registers to avoid X propagation.
        uut.IF_ID_IR = 0; uut.IF_ID_NPC = 0;
        uut.ID_EX_IR = 0; uut.ID_EX_NPC = 0; uut.ID_EX_A = 0; uut.ID_EX_B = 0; uut.ID_EX_IMM = 0; uut.ID_EX_type = 0;
        uut.EX_MEM_IR = 0; uut.EX_MEM_ALUOut = 0; uut.EX_MEM_B = 0; uut.EX_MEM_cond = 0; uut.EX_MEM_type = 0;
        uut.MEM_WB_IR = 0; uut.MEM_WB_ALUOut = 0; uut.MEM_WB_LMD = 0; uut.MEM_WB_type = 0;

        $dumpfile("artifacts/vcd/tb_add_three_numbers.vcd");
        $dumpvars(0, tb_add_three_numbers);

        repeat (50) begin
            #5 clock1 = 1; #5 clock1 = 0;
            #5 clock2 = 1; #5 clock2 = 0;
        end

        if (uut.rf.regs[5] == 32'd55)
            $display("PASS: R5 = %0d", uut.rf.regs[5]);
        else
            $display("FAIL: R5 = %0d, expected 55", uut.rf.regs[5]);

        $finish;
    end
endmodule
