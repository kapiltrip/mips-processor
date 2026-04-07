`timescale 1ns/1ps

module tb_factorial;
    reg clock1, clock2;
    integer k;

    mips uut(.clock1(clock1), .clock2(clock2));

    initial begin
        clock1 = 0;
        clock2 = 0;

        for (k = 0; k < 32; k = k + 1)
            uut.rf.regs[k] = k;

        // Program: compute factorial of Mem[200] and store result in Mem[198].
        uut.memory.mem[0]  = 32'h280a00c8; // ADDI R10, R0, 200
        uut.memory.mem[1]  = 32'h28020001; // ADDI R2, R0, 1
        uut.memory.mem[2]  = 32'h35430000; // LW R3, 0(R10)
        uut.memory.mem[3]  = 32'h14e73800; // OR R7, R7, R7
        uut.memory.mem[4]  = 32'h10431000; // MUL R2, R3, R2
        uut.memory.mem[5]  = 32'h14e73800; // OR R7, R7, R7
        uut.memory.mem[6]  = 32'h2c630001; // SUBI R3, R3, 1
        uut.memory.mem[7]  = 32'h14e73800; // OR R7, R7, R7
        uut.memory.mem[8]  = 32'h3c60fffb; // BNEQZ R3, loop (-5)
        uut.memory.mem[9]  = 32'h3942fffe; // SW R2, -2(R10)
        uut.memory.mem[10] = 32'hfc000000; // HLT

        uut.memory.mem[200] = 32'd7;

        uut.PC = 0;
        uut.halted = 0;
        uut.taken_branch = 0;

        // Initialize pipeline registers to avoid X propagation.
        uut.IF_ID_IR = 0; uut.IF_ID_NPC = 0;
        uut.ID_EX_IR = 0; uut.ID_EX_NPC = 0; uut.ID_EX_A = 0; uut.ID_EX_B = 0; uut.ID_EX_IMM = 0; uut.ID_EX_type = 0;
        uut.EX_MEM_IR = 0; uut.EX_MEM_ALUOut = 0; uut.EX_MEM_B = 0; uut.EX_MEM_cond = 0; uut.EX_MEM_type = 0;
        uut.MEM_WB_IR = 0; uut.MEM_WB_ALUOut = 0; uut.MEM_WB_LMD = 0; uut.MEM_WB_type = 0;

        $dumpfile("artifacts/vcd/tb_factorial.vcd");
        $dumpvars(0, tb_factorial);

        repeat (200) begin
            #5 clock1 = 1; #5 clock1 = 0;
            #5 clock2 = 1; #5 clock2 = 0;
        end

        if (uut.memory.mem[198] == 32'd5040)
            $display("PASS: Mem[198] = %0d", uut.memory.mem[198]);
        else
            $display("FAIL: Mem[198] = %0d, expected 5040", uut.memory.mem[198]);

        $finish;
    end
endmodule
