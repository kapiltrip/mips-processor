# Lecture 27 — DATAPATH AND CONTROLLER DESIGN (PART 3)

Deep notes from the transcript: signed multiplication using Booth’s algorithm; datapath/control partitioning; Verilog RTL structure; verification and timing caveats.

## Why Booth’s Algorithm
- Goal: multiply signed two’s‑complement numbers efficiently.
- Conventional shift‑add (iterative): W iterations, each does “if Q0==1 then P+=M; shift”. Requires up to W additions and W shifts.
- Booth’s improvement: examine two bits at a time (Q0, Q−1). Shifts every cycle (still W) but reduces number of add/sub operations by collapsing runs of 1s/0s.
  - Rules for pair (Q0, Q−1):
    - 00 or 11 → no add/sub; just arithmetic right shift of (A:Q:Q−1).
    - 01 → A := A + M; then arithmetic right shift.
    - 10 → A := A − M; then arithmetic right shift.
  - Initialize Q−1 = 0. After each step, decrement count; stop after W shifts.
  - Final product is the 2W‑bit concatenation (A:Q).

## Numeric Conventions
- Two’s‑complement inputs: multiplicand M[W−1:0], multiplier Q[W−1:0].
- Accumulator A[W−1:0] begins at 0.
- Arithmetic right shift of the concatenation (A:Q:Q−1) replicates A’s sign bit into A’s MSB.

## Worked Examples (from lecture)
1) W=5, M = −10 (10110₂), Q = +13 (01101₂)
   - Initialize: A=00000, Q=01101, Q−1=0
   - Sequence (showing pair, action, then shift):
     - (Q0,Q−1)=(1,0) → A:=A−M (i.e., A+=−M=01010) → shift arith
     - (1,1) → no add/sub → shift
     - (0,1) → A:=A+M → shift
     - (1,0) → A:=A−M → shift
     - (0,1) → A:=A+M → shift → done → Product = A:Q = −130₁₀
2) W=6, M = −31, Q = +28
   - Many cycles are “00” or “11”, so adds happen only twice, illustrating reduced operations.

## Datapath Architecture
- Storage
  - `A[W-1:0]`: accumulator (needs clear, load_from_ALU, and arithmetic right shift).
  - `Q[W-1:0]`: multiplier (load from input; arithmetic right shift).
  - `Qm1`: single flip‑flop holding previous Q0 (clearable at start; captures Q[0] on shift).
  - `M[W-1:0]`: multiplicand (parallel‑load from input; static during run).
  - `COUNT`: loop counter (load W, then decrement; exposes zero status `cnt_zero`).
- Functional
  - `ALU`: add/sub between A and M, controlled by `add_sub` (1:add, 0:sub or vice‑versa—define explicitly).
- Status signals to controller
  - `Q0 = Q[0]` and `Qm1` (the pair determines action).
  - `cnt_zero` (1 when COUNT==0) to terminate after W shifts.
- Control signals to datapath
  - `loadM`, `loadQ`, `clearA`, `loadA_from_ALU`, `shiftAQ` (arith right shift across A:Q:Qm1), `clrQm1`, `loadCnt`, `decCnt`, `addSub`.

### Arithmetic Right Shift Across A:Q:Qm1
For one cycle when `shiftAQ` is asserted at the rising edge:
- `Qm1_next <= Q[0]`.
- `Q_next   <= { A[0], Q[W-1:1] }`.
- `A_next   <= { A[W-1], A[W-1:1] }` (sign‑extend A).

## Controller FSM
- States
  - `S0` Idle: wait for `start`.
  - `S1` Load M, clear A & Qm1, load COUNT=W (can be done in same cycle), prepare for Q load.
  - `S2` Load Q.
  - `S3` Add phase (01): A := A + M; then go to shift state.
  - `S4` Sub phase (10): A := A − M; then go to shift state.
  - `S5` Shift: arithmetic right shift A:Q:Qm1; decrement COUNT; branch based on `(Q0,Qm1)` and `cnt_zero`.
  - `S6` Done: assert `done`.
- Transitions
  - `S0 → S1` on `start`.
  - `S1 → S2` next cycle.
  - `S2 → S3` if (Q0,Qm1)==01; `S2 → S4` if 10; `S2 → S5` if 00 or 11.
  - `S3 → S5`; `S4 → S5`.
  - `S5 → S6` if `cnt_zero==1`; else `S5 → S3` on 01; `S5 → S4` on 10; else `S5 → S5`.
  - `S6` holds until re‑arm policy.
- Outputs (Moore)
  - `S1`: `loadM=1, clearA=1, clrQm1=1, loadCnt=1` (COUNT←W), `addSub=X`.
  - `S2`: `loadQ=1`.
  - `S3`: `addSub=ADD; loadA_from_ALU=1`.
  - `S4`: `addSub=SUB; loadA_from_ALU=1`.
  - `S5`: `shiftAQ=1; decCnt=1`.
  - `S6`: `done=1`.

## Verilog RTL Skeleton
Parameterized width W (default 16). Two‑process FSM style in controller.

### Datapath
```verilog
module booth_datapath #(parameter W=16)(
  input  wire         clk,
  // controls
  input  wire         loadM, loadQ,
  input  wire         clearA, loadA_from_ALU,
  input  wire         shiftAQ, clrQm1,
  input  wire         loadCnt, decCnt,
  input  wire         addSub, // 1:add (A+M), 0:sub (A-M)
  // IO
  input  wire [W-1:0] data_in,
  output wire         Q0, Qm1,
  output wire         cnt_zero,
  output wire [W-1:0] A_out, Q_out // observability
);
  // registers
  reg [W-1:0] A, Q, M;
  reg         q_m1;
  reg [$clog2(W+1)-1:0] COUNT; // enough bits to count W..0

  // status
  assign Q0 = Q[0];
  assign Qm1 = q_m1;
  assign A_out = A; assign Q_out = Q;
  assign cnt_zero = (COUNT == 0);

  // ALU
  wire [W-1:0] add_res = A + M;
  wire [W-1:0] sub_res = A - M;
  wire [W-1:0] alu_z   = addSub ? add_res : sub_res;

  // sequential behavior
  always @(posedge clk) begin
    // M and Q loads
    if (loadM) M <= data_in;
    if (loadQ) Q <= data_in;

    // A load/clear
    if (clearA) A <= {W{1'b0}};
    else if (loadA_from_ALU) A <= alu_z;

    // Q-1 clear
    if (clrQm1) q_m1 <= 1'b0;

    // COUNT control
    if (loadCnt) COUNT <= W[$clog2(W+1)-1:0];
    else if (decCnt) COUNT <= COUNT - 1'b1;

    // Arithmetic right shift of (A:Q:q_m1)
    if (shiftAQ) begin
      q_m1 <= Q[0];
      Q    <= {A[0], Q[W-1:1]};
      A    <= {A[W-1], A[W-1:1]}; // sign extend
    end
  end
endmodule
```

### Controller (two‑process FSM)
```verilog
module booth_controller(
  input  wire clk,
  input  wire start,
  input  wire Q0, Qm1, cnt_zero,
  output reg  loadM, loadQ, clearA, loadA_from_ALU,
  output reg  shiftAQ, clrQm1, loadCnt, decCnt, addSub,
  output reg  done
);
  typedef enum reg [2:0] {S0, S1, S2, S3, S4, S5, S6} state_t; // SystemVerilog
  state_t s, ns;

  // state register
  always @(posedge clk) s <= ns;

  // next-state and output logic (Moore)
  always @* begin
    {loadM,loadQ,clearA,loadA_from_ALU,shiftAQ,clrQm1,loadCnt,decCnt,addSub,done} = '0;
    ns = s;
    case (s)
      S0: begin ns = start ? S1 : S0; end
      S1: begin // load M, clear A & Q-1, load COUNT=W
        loadM=1; clearA=1; clrQm1=1; loadCnt=1; ns = S2;
      end
      S2: begin // load Q then branch on (Q0,Qm1)
        loadQ=1; // decide next state based on current Q0/Qm1 (from previous content if any)
        unique case ({Q0,Qm1})
          2'b01: ns = S3;     // add
          2'b10: ns = S4;     // sub
          default: ns = S5;   // 00 or 11 → shift only
        endcase
      end
      S3: begin // A := A + M
        addSub=1; loadA_from_ALU=1; ns = S5;
      end
      S4: begin // A := A - M
        addSub=0; loadA_from_ALU=1; ns = S5;
      end
      S5: begin // shift and count
        shiftAQ=1; decCnt=1;
        if (cnt_zero) ns = S6;
        else begin
          unique case ({Q0,Qm1})
            2'b01: ns = S3;
            2'b10: ns = S4;
            default: ns = S5; // keep shifting on 00/11
          endcase
        end
      end
      S6: begin done=1; ns = S6; end
      default: ns = S0;
    endcase
  end
endmodule
```

### Integration Top
```verilog
module booth_top #(parameter W=16)(
  input  wire         clk,
  input  wire         start,
  input  wire [W-1:0] data_in,
  output wire [2*W-1:0] product,
  output wire         done
);
  wire loadM, loadQ, clearA, loadA_from_ALU, shiftAQ, clrQm1, loadCnt, decCnt, addSub;
  wire Q0, Qm1, cnt_zero; wire [W-1:0] A_out, Q_out;
  booth_datapath #(.W(W)) dp(
    .clk(clk), .loadM(loadM), .loadQ(loadQ), .clearA(clearA), .loadA_from_ALU(loadA_from_ALU),
    .shiftAQ(shiftAQ), .clrQm1(clrQm1), .loadCnt(loadCnt), .decCnt(decCnt), .addSub(addSub),
    .data_in(data_in), .Q0(Q0), .Qm1(Qm1), .cnt_zero(cnt_zero), .A_out(A_out), .Q_out(Q_out)
  );
  booth_controller ctl(
    .clk(clk), .start(start), .Q0(Q0), .Qm1(Qm1), .cnt_zero(cnt_zero),
    .loadM(loadM), .loadQ(loadQ), .clearA(clearA), .loadA_from_ALU(loadA_from_ALU),
    .shiftAQ(shiftAQ), .clrQm1(clrQm1), .loadCnt(loadCnt), .decCnt(decCnt), .addSub(addSub), .done(done)
  );
  assign product = {A_out, Q_out};
endmodule
```

## Testbench Guidance and Timing
- Align input drives to the intended load states:
  - Present M on `data_in` for `S1` cycle; present Q on `data_in` for `S2` cycle.
- Start pulse: assert `start` before the next rising edge while in `S0`.
- Clock example: `always #5 clk = ~clk;`.
- End condition: wait on `done==1`; product available on `{A_out,Q_out}`.
- Timing caveat (from lecture): even if simulation uses zero delays, real hardware has nonzero delays; write testbenches that respect cycle boundaries and do not depend on delta‑cycle ordering.

Self‑checking scaffold (concept)
```systemverilog
task do_mul(input logic signed [W-1:0] M, input logic signed [W-1:0] Q);
  @(posedge clk); data_in<=M; start<=1; @(posedge clk); start<=0; // S1
  @(posedge clk); data_in<=Q;                                     // S2
  wait(done); @(posedge clk);
  assert($signed(product) == $signed(M)*$signed(Q)) else $fatal("Mismatch");
endtask
```

## Correctness Invariants
- Let `PP = {A,Q}` sign‑extended when interpreted as signed 2W‑bit number. After k iterations (k shifts), `PP` equals `M` multiplied by the Booth‑decoded value of the k least‑significant processed bits of Q, plus the contribution of remaining bits yet to be processed. After W iterations, `PP = M×Q`.
- Monotone progress: COUNT decreases by 1 each shift; termination is guaranteed after W shifts.
- Pair logic safety: exactly one of {01,10,00/11} holds each cycle; pairs 00/11 should never trigger add/sub.

## Common Pitfalls and Fixes
- Using logical shift instead of arithmetic shift on A → sign corruption. Fix: replicate `A[W-1]` into A’s MSB during shift.
- Updating `Qm1` from A or a stale Q bit → must set `Qm1_next = Q[0]` concurrently with Q’s shift.
- Off‑by‑one COUNT: initialize to W and decrement after every shift; exit when COUNT==0 post‑shift.
- Add/Sub polarity mismatch between spec and ALU control; document `addSub` convention and stick to it.
- Loading M and Q in the same cycle with a single input bus — the datapath uses `sel_in` implicitly by distinct states; keep loads in S1/S2.

## Performance and Variants
- Cycle count: exactly W shifts; add/sub occurs only on transitions in multiplier bit pattern. Worst case is still ~W operations; typical is less.
- Radix‑4 Booth: inspect 3 bits (Q1:Q0:Q−1); recode into {−2,−1,0,+1,+2}; halves shift count to W/2 with wider add (shifted M by 1 for ×2). Datapath: needs an extra left‑shift of M and a small recoder.

## Synthesis Notes
- Controller encoding: one‑hot may improve Fmax on FPGA; binary saves area.
- Use register enables for A/Q to map onto CE pins.
- The concatenated shift is implemented with simple routing; no barrel shifters are required.

## Exercise Ideas
- Add synchronous reset `rst` and busy/ready handshake.
- Implement a Radix‑4 Booth controller and datapath with a small recoder and `A := A + {−2M,−M,0,+M,+2M}`.
- Create a cycle counter and compare conventional shift‑add vs. Booth on random signed pairs.

---
End of deep notes for Lecture 27.

