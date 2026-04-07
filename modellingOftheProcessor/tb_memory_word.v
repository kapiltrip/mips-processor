`timescale 1ns/1ps

module tb_memory_word;
    reg clock1, clock2;
    integer k;

    mips uut(.clock1(clock1), .clock2(clock2));

    initial begin
        clock1 = 0;
        clock2 = 0;

        // Initialize registers.
        for (k = 0; k < 32; k = k + 1)
            uut.rf.regs[k] = k;

        // Program: load Mem[120], add 45, store to Mem[121].
        uut.memory.mem[0] = 32'h28010078; // ADDI R1, R0, 120
        uut.memory.mem[1] = 32'h14631800; // OR R3, R3, R3
        uut.memory.mem[2] = 32'h34220000; // LW R2, 0(R1)
        uut.memory.mem[3] = 32'h14631800; // OR R3, R3, R3
        uut.memory.mem[4] = 32'h2842002d; // ADDI R2, R2, 45
        uut.memory.mem[5] = 32'h14631800; // OR R3, R3, R3
        uut.memory.mem[6] = 32'h38220001; // SW R2, 1(R1)
        uut.memory.mem[7] = 32'hfc000000; // HLT

        uut.memory.mem[120] = 32'd85;

        uut.PC = 0;
        uut.halted = 0;
        uut.taken_branch = 0;

        // Initialize pipeline registers to avoid X propagation.
        uut.IF_ID_IR = 0; uut.IF_ID_NPC = 0;
        uut.ID_EX_IR = 0; uut.ID_EX_NPC = 0; uut.ID_EX_A = 0; uut.ID_EX_B = 0; uut.ID_EX_IMM = 0; uut.ID_EX_type = 0;
        uut.EX_MEM_IR = 0; uut.EX_MEM_ALUOut = 0; uut.EX_MEM_B = 0; uut.EX_MEM_cond = 0; uut.EX_MEM_type = 0;
        uut.MEM_WB_IR = 0; uut.MEM_WB_ALUOut = 0; uut.MEM_WB_LMD = 0; uut.MEM_WB_type = 0;

        $dumpfile("artifacts/vcd/tb_memory_word.vcd");
        $dumpvars(0, tb_memory_word);

        repeat (60) begin
            #5 clock1 = 1; #5 clock1 = 0;
            #5 clock2 = 1; #5 clock2 = 0;
        end

        if (uut.memory.mem[121] == 32'd130)
            $display("PASS: Mem[121] = %0d", uut.memory.mem[121]);
        else
            $display("FAIL: Mem[121] = %0d, expected 130", uut.memory.mem[121]);

        $finish;
    end
endmodule
