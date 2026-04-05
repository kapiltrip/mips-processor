`timescale 1ns/1ps

module tb_add_three_numbers;
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
    wire [31:0] R0 = uut.rf.regs[0];
    wire [31:0] R1 = uut.rf.regs[1];
    wire [31:0] R2 = uut.rf.regs[2];
    wire [31:0] R3 = uut.rf.regs[3];
    wire [31:0] R4 = uut.rf.regs[4];
    wire [31:0] R5 = uut.rf.regs[5];
    wire [31:0] R7 = uut.rf.regs[7];

    wire [31:0] IMEM0 = uut.memory.mem[0];
    wire [31:0] IMEM1 = uut.memory.mem[1];
    wire [31:0] IMEM2 = uut.memory.mem[2];
    wire [31:0] IMEM3 = uut.memory.mem[3];
    wire [31:0] IMEM4 = uut.memory.mem[4];
    wire [31:0] IMEM5 = uut.memory.mem[5];
    wire [31:0] IMEM6 = uut.memory.mem[6];
    wire [31:0] IMEM7 = uut.memory.mem[7];
    wire [31:0] IMEM8 = uut.memory.mem[8];

    initial begin
        clock1 = 0; clock2 = 0;
        wait (init_done);
        repeat (50) begin
            #5 clock1 = 1; #5 clock1 = 0;
            #5 clock2 = 1; #5 clock2 = 0;
        end
    end

    initial begin
        init_done = 0;
        #0;
        // Initialize register file for visibility
        for (k = 0; k < 32; k = k + 1) begin
            uut.rf.regs[k] = k;
        end

        // Program: add 10, 20, 25 and store final sum in R5
        uut.memory.mem[0] = 32'h2801000a; // ADDI R1, R0, 10
        uut.memory.mem[1] = 32'h28020014; // ADDI R2, R0, 20
        uut.memory.mem[2] = 32'h28030019; // ADDI R3, R0, 25
        uut.memory.mem[3] = 32'h14e73800; // OR R7, R7, R7 (dummy)
        uut.memory.mem[4] = 32'h14e73800; // OR R7, R7, R7 (dummy)
        uut.memory.mem[5] = 32'h00222000; // ADD R4, R1, R2
        uut.memory.mem[6] = 32'h14e73800; // OR R7, R7, R7 (dummy)
        uut.memory.mem[7] = 32'h00832800; // ADD R5, R4, R3
        uut.memory.mem[8] = 32'hfc000000; // HLT

        // Reset control flags and PC
        uut.PC = 0; uut.halted = 0; uut.taken_branch = 0;

        // Initialize pipeline regs for cleaner waveforms (avoids X-propagation).
        uut.IF_ID_IR = 0; uut.IF_ID_NPC = 0;
        uut.ID_EX_IR = 0; uut.ID_EX_NPC = 0; uut.ID_EX_A = 0; uut.ID_EX_B = 0; uut.ID_EX_IMM = 0; uut.ID_EX_type = 0;
        uut.EX_MEM_IR = 0; uut.EX_MEM_ALUOut = 0; uut.EX_MEM_B = 0; uut.EX_MEM_cond = 0; uut.EX_MEM_type = 0;
        uut.MEM_WB_IR = 0; uut.MEM_WB_ALUOut = 0; uut.MEM_WB_LMD = 0; uut.MEM_WB_type = 0;

        init_done = 1;

        // Finish after enough time for program
        #500;
        for (k = 0; k <= 5; k = k + 1) begin
            $display("R%0d: %0d", k, uut.rf.regs[k]);
        end
        $finish;
    end

    initial begin
        wait (init_done);
        $dumpfile("tb_add_three_numbers.vcd");
        $dumpvars(1, tb_add_three_numbers);
    end
endmodule
