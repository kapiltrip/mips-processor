// Simple pipelined MIPS-like processor based on lecture transcript
`timescale 1ns/1ps
module mips(input clock1, input clock2);
    // Program counter
    reg [31:0] PC;

    // IF/ID pipeline registers
    reg [31:0] IF_ID_IR, IF_ID_NPC;

    // ID/EX pipeline registers
    reg [31:0] ID_EX_IR, ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_IMM;
    reg [2:0]  ID_EX_type;

    // EX/MEM pipeline registers
    reg [31:0] EX_MEM_IR, EX_MEM_ALUOut, EX_MEM_B;
    reg        EX_MEM_cond;
    reg [2:0]  EX_MEM_type;

    // MEM/WB pipeline registers
    reg [31:0] MEM_WB_IR, MEM_WB_ALUOut, MEM_WB_LMD;
    reg [2:0]  MEM_WB_type;

    // Opcodes
    parameter ADD   = 6'b000000,
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
    parameter RR_ALU = 3'b000,
              RM_ALU = 3'b001,
              LOAD   = 3'b010,
              STORE  = 3'b011,
              BRANCH = 3'b100,
              HALT   = 3'b101;

    // Control flags
    reg halted, taken_branch;

    // Decode / datapath modules
    wire [2:0]  dec_type;
    wire [31:0] rf_rd1, rf_rd2;

    wire        rf_we;
    wire [4:0]  rf_wa;
    wire [31:0] rf_wd;

    wire        branch_taken;
    wire [31:0] ifetch_addr;
    wire [31:0] instr_word;

    wire        mem_we;
    wire [31:0] mem_data_out;

    wire [31:0] alu_a, alu_b, alu_out;

    control_unit cu(
        .opcode(IF_ID_IR[31:26]),
        .instr_type(dec_type)
    );

    regfile rf(
        .clock(clock1),
        .we(rf_we),
        .ra1(IF_ID_IR[25:21]),
        .ra2(IF_ID_IR[20:16]),
        .wa(rf_wa),
        .wd(rf_wd),
        .rd1(rf_rd1),
        .rd2(rf_rd2)
    );

    memory_interface memory(
        .clock(clock2),
        .instr_addr(ifetch_addr),
        .instr_out(instr_word),
        .data_addr(EX_MEM_ALUOut),
        .data_in(EX_MEM_B),
        .data_out(mem_data_out),
        .data_we(mem_we)
    );

    alu alu_unit(
        .opcode(ID_EX_IR[31:26]),
        .a(alu_a),
        .b(alu_b),
        .result(alu_out)
    );

    assign branch_taken =
        ((EX_MEM_IR[31:26] === BEQZ)  && (EX_MEM_cond === 1'b1)) ||
        ((EX_MEM_IR[31:26] === BNEQZ) && (EX_MEM_cond === 1'b0));

    assign ifetch_addr = branch_taken ? EX_MEM_ALUOut : PC;

    assign alu_a = (ID_EX_type == BRANCH) ? ID_EX_NPC : ID_EX_A;
    assign alu_b = (ID_EX_type == RR_ALU) ? ID_EX_B : ID_EX_IMM;

    assign mem_we = (!halted) && (EX_MEM_type == STORE) && (!taken_branch);

    assign rf_wa = (MEM_WB_type == RR_ALU) ? MEM_WB_IR[15:11] : MEM_WB_IR[20:16];
    assign rf_wd = (MEM_WB_type == LOAD) ? MEM_WB_LMD : MEM_WB_ALUOut;
    assign rf_we =
        (!taken_branch) &&
        ((MEM_WB_type == RR_ALU) || (MEM_WB_type == RM_ALU) || (MEM_WB_type == LOAD)) &&
        (rf_wa != 5'd0);

    initial begin
        PC = 0;
        halted = 0;
        taken_branch = 0;
    end

    // Instruction Fetch
    always @(posedge clock1) begin
        if (!halted) begin
            IF_ID_IR  <= instr_word;
            IF_ID_NPC <= ifetch_addr + 1;
            PC        <= ifetch_addr + 1;
            taken_branch <= branch_taken;
        end
    end

    // Instruction Decode
    always @(posedge clock2) begin
        if (!halted) begin
            ID_EX_NPC <= IF_ID_NPC;
            ID_EX_IR  <= IF_ID_IR;

            // Register operand fetch with R0 hardwired to zero
            ID_EX_A <= rf_rd1;
            ID_EX_B <= rf_rd2;

            // Sign-extended immediate
            ID_EX_IMM <= {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]};

            // Determine instruction type
            ID_EX_type <= dec_type;
        end
    end

    // Execute
    always @(posedge clock1) begin
        if (!halted) begin
            EX_MEM_type <= ID_EX_type;
            EX_MEM_IR   <= ID_EX_IR;
            EX_MEM_ALUOut <= (ID_EX_type == HALT) ? 32'd0 : alu_out;
            EX_MEM_B      <= ID_EX_B;
            EX_MEM_cond   <= (ID_EX_A == 0);//its checking the condition , here, to branch or not .
        end
    end

    // Memory access
    always @(posedge clock2) begin
        if (!halted) begin
            MEM_WB_type   <= EX_MEM_type;
            MEM_WB_IR     <= EX_MEM_IR;
            MEM_WB_ALUOut <= EX_MEM_ALUOut;

            case (EX_MEM_type)
                LOAD: begin
                    MEM_WB_LMD <= mem_data_out;
                end
                default: ;
            endcase
        end
    end

    // Write back
    always @(posedge clock1) begin
        if (!taken_branch) begin
            case (MEM_WB_type)
                HALT: halted <= 1'b1;
                default: ;
            endcase
        end
    end
endmodule
