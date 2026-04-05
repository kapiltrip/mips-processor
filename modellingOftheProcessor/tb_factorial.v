`timescale 1ns/1ps

module tb_factorial;
    reg clock1, clock2;
    mips uut(.clock1(clock1), .clock2(clock2));

    integer k;
    reg init_done;

    // Core pipeline/debug signals (flattened into TB scope for clean VCDs).
    wire [31:0] PC = uut.PC;
    wire [31:0] ifetch_addr = uut.ifetch_addr;
    wire [31:0] instr_word = uut.instr_word;

    wire [31:0] IF_ID_IR = uut.IF_ID_IR;
    wire [31:0] IF_ID_NPC = uut.IF_ID_NPC;

    wire [31:0] ID_EX_IR = uut.ID_EX_IR;
    wire [31:0] ID_EX_NPC = uut.ID_EX_NPC;
    wire [31:0] ID_EX_A = uut.ID_EX_A;
    wire [31:0] ID_EX_B = uut.ID_EX_B;
    wire [31:0] ID_EX_IMM = uut.ID_EX_IMM;
    wire [2:0]  ID_EX_type = uut.ID_EX_type;

    wire [31:0] alu_a = uut.alu_a;
    wire [31:0] alu_b = uut.alu_b;
    wire [31:0] alu_out = uut.alu_out;

    wire [31:0] EX_MEM_IR = uut.EX_MEM_IR;
    wire [31:0] EX_MEM_ALUOut = uut.EX_MEM_ALUOut;
    wire [31:0] EX_MEM_B = uut.EX_MEM_B;
    wire        EX_MEM_cond = uut.EX_MEM_cond;
    wire [2:0]  EX_MEM_type = uut.EX_MEM_type;

    wire        mem_we = uut.mem_we;
    wire [31:0] mem_data_out = uut.mem_data_out;

    wire [31:0] MEM_WB_IR = uut.MEM_WB_IR;
    wire [31:0] MEM_WB_ALUOut = uut.MEM_WB_ALUOut;
    wire [31:0] MEM_WB_LMD = uut.MEM_WB_LMD;
    wire [2:0]  MEM_WB_type = uut.MEM_WB_type;

    wire        rf_we = uut.rf_we;
    wire [4:0]  rf_wa = uut.rf_wa;
    wire [31:0] rf_wd = uut.rf_wd;

    wire        branch_taken = uut.branch_taken;
    wire        taken_branch = uut.taken_branch;
    wire        halted = uut.halted;

    // Waveform-friendly aliases (avoid dumping array elements directly).
    wire [31:0] R0  = uut.rf.regs[0];
    wire [31:0] R2  = uut.rf.regs[2];
    wire [31:0] R3  = uut.rf.regs[3];
    wire [31:0] R7  = uut.rf.regs[7];
    wire [31:0] R10 = uut.rf.regs[10];

    wire [31:0] IMEM0  = uut.memory.mem[0];
    wire [31:0] IMEM1  = uut.memory.mem[1];
    wire [31:0] IMEM2  = uut.memory.mem[2];
    wire [31:0] IMEM3  = uut.memory.mem[3];
    wire [31:0] IMEM4  = uut.memory.mem[4];
    wire [31:0] IMEM5  = uut.memory.mem[5];
    wire [31:0] IMEM6  = uut.memory.mem[6];
    wire [31:0] IMEM7  = uut.memory.mem[7];
    wire [31:0] IMEM8  = uut.memory.mem[8];
    wire [31:0] IMEM9  = uut.memory.mem[9];
    wire [31:0] IMEM10 = uut.memory.mem[10];

    wire [31:0] MEM198 = uut.memory.mem[198];
    wire [31:0] MEM200 = uut.memory.mem[200];

    initial begin
        clock1 = 0; clock2 = 0;
        wait (init_done);
        repeat (200) begin
            #5 clock1 = 1; #5 clock1 = 0;
            #5 clock2 = 1; #5 clock2 = 0;
        end
    end

    initial begin
        init_done = 0;
        #0;
        for (k = 0; k < 32; k = k + 1) begin
            uut.rf.regs[k] = k;
        end

        // Program to compute factorial of the value stored at Mem[200]
        uut.memory.mem[0]  = 32'h280a00c8; // ADDI R10, R0, 200
        uut.memory.mem[1]  = 32'h28020001; // ADDI R2,  R0, 1 (accumulator)
        uut.memory.mem[2]  = 32'h35430000; // LW   R3, 0(R10) load N
        uut.memory.mem[3]  = 32'h14e73800; // OR   R7, R7, R7 (dummy)
        uut.memory.mem[4]  = 32'h10431000; // MUL  R2, R3, R2
        uut.memory.mem[5]  = 32'h14e73800; // OR   R7, R7, R7 (dummy)
        uut.memory.mem[6]  = 32'h2c630001; // SUBI R3, R3, 1
        uut.memory.mem[7]  = 32'h14e73800; // OR   R7, R7, R7 (dummy)
        uut.memory.mem[8]  = 32'h3c60fffb; // BNEQZ R3, loop (-5)
        uut.memory.mem[9]  = 32'h3942fffe; // SW   R2, -2(R10)
        uut.memory.mem[10] = 32'hfc000000; // HLT

        // Place input value N at Mem[200]
        uut.memory.mem[200] = 32'd7;

        // Reset PC and flags
        uut.PC = 0; uut.halted = 0; uut.taken_branch = 0;

        // Initialize pipeline regs for cleaner waveforms (avoids X-propagation).
        uut.IF_ID_IR = 0; uut.IF_ID_NPC = 0;
        uut.ID_EX_IR = 0; uut.ID_EX_NPC = 0; uut.ID_EX_A = 0; uut.ID_EX_B = 0; uut.ID_EX_IMM = 0; uut.ID_EX_type = 0;
        uut.EX_MEM_IR = 0; uut.EX_MEM_ALUOut = 0; uut.EX_MEM_B = 0; uut.EX_MEM_cond = 0; uut.EX_MEM_type = 0;
        uut.MEM_WB_IR = 0; uut.MEM_WB_ALUOut = 0; uut.MEM_WB_LMD = 0; uut.MEM_WB_type = 0;

        init_done = 1;

        // Monitor accumulator as it changes
        $monitor("Time=%0t R2=%0d", $time, uut.rf.regs[2]);

        #3000;
        $display("Mem[200]: %0d", uut.memory.mem[200]);
        $display("Mem[198]: %0d", uut.memory.mem[198]);
        $finish;
    end

    initial begin
        wait (init_done);
        $dumpfile("tb_factorial.vcd");
        $dumpvars(1, tb_factorial);
    end
endmodule
