# Lecture 25 — DATAPATH AND CONTROLLER DESIGN (PART 1)

Deep, single-file notes derived from the lecture transcript you provided.

## Learning Goals
- Understand why complex digital systems are split into a Datapath and a Controller (FSM).
- Learn to translate an algorithm into a microarchitecture: storage, functional units, interconnect, control, and status.
- Practice building an FSM that sequences a datapath to realize a computation.
- Code the design in Verilog at a clean behavioral/structural boundary and verify with a simple testbench.

## Big Picture: Datapath vs Controller
- Datapath
  - Contains the hardware that holds and transforms data: registers, counters, adders/subtractors, multipliers, multiplexers, buses, comparators.
  - Produces status signals (e.g., zero, carry, overflow) that summarize the current data condition.
  - Does not decide when/why to operate; it executes operations when control signals are asserted.
- Controller (Control Path)
  - A finite state machine that sequences control signals per clock to drive the datapath.
  - Consumes datapath status to determine next states and when an operation is complete.
  - Provides external handshake: typically `start` to begin and `done` to indicate completion.

## Design Recipe (repeatable checklist)
1) Start from the algorithm/behavioral spec; define data width W and numeric conventions (unsigned/signed).
2) Identify required storage (registers/counters) and functional units (add, sub, compare, muxes).
3) Define visible interface: `clk`, `reset` policy, input/output ports, `start/done` semantics.
4) Sketch the datapath: draw blocks and wires; decide where values live each cycle.
5) Enumerate control signals (inputs to datapath) and status signals (outputs from datapath).
6) Write a cycle-by-cycle schedule and then the FSM states and transitions.
7) Code datapath and controller as separate modules; keep timing and resets consistent.
8) Create a focused testbench to validate the key behavior and corner cases.

## Warm‑up Example: a = b + c; d = a − c
- Datapath: registers `A`, `B`, `C`, `D`; `Adder` and `Subtractor`.
- Control: `loadA` (capture `B+C` in A), `loadD` (capture `A−C` in D).
- Minimal FSM schedule (Moore)
  - S1: assert `loadA` for one cycle.
  - S2: assert `loadD` for one cycle; then idle/done.
  - Demonstrates the separation: datapath wires are fixed; only sequencing differs per algorithm.

## Core Example: Multiplication by Repeated Addition
Goal: compute `P = A × B` by repeated addition (introductory iterative multiplier).

### Algorithm (basic, B > 0 assumed in this version)
- Initialize `P = 0`.
- Repeat `B` times: `P = P + A`; `B = B − 1`.

### Interface and Types (suggested)
- Parameterizable width `W = 16` (from the lecture examples).
- Inputs: `clk`, `start`, `data_in[W-1:0]`.
- Outputs: `done`; product available on the output of register `P` (can be probed internally or exposed).

### Datapath Microarchitecture
- Storage
  - `A`: parallel-in/parallel-out (PIPO) register with `loadA`.
  - `B`: down counter with `loadB` and `decB`, output `B_out`.
  - `P`: PIPO register with `loadP` and `clearP`.
- Functional Units
  - `Adder`: inputs `A_out (x)` and `P_out (y)`, output `Z`.
  - `Zero Comparator`: checks `B_out == 0` → status `eqZ` (1 when zero). Often coded as reduction NOR: `assign eqZ = ~|B_out;`.
- Interconnect
  - `data_in` feeds either A or B depending on `loadA`/`loadB` sequencing.
  - `Z` feeds back into `P` when `loadP` is high.
- Control and Status
  - Controls to datapath: `loadA`, `loadB`, `loadP`, `clearP`, `decB`.
  - Status to controller: `eqZ` (B has reached zero).

### Controller (Moore FSM, 5 states)
- States
  - `S0` Idle: wait for `start`.
  - `S1` Load A.
  - `S2` Load B and clear P.
  - `S3` Loop body: accumulate (`loadP`) and decrement (`decB`).
  - `S4` Done: assert `done`.
- Next-state logic
  - `S0 → S1` when `start == 1`.
  - `S1 → S2` on next clock.
  - `S2 → S3` on next clock.
  - `S3 → S3` while `eqZ == 0` (keep iterating), else `S3 → S4` when `eqZ == 1`.
  - `S4` holds (or returns to `S0` on a new `start`, per system policy).
- Output decoding (per state)
  - `S0`: all control signals 0.
  - `S1`: `loadA = 1`.
  - `S2`: `loadB = 1`, `clearP = 1`.
  - `S3`: `loadP = 1`, `decB = 1` each cycle.
  - `S4`: `done = 1`.

### Cycle‑Accurate Schedule (example A=17, B=5)
- Assume `start` asserted; data `17` then `5` are presented to `data_in` in consecutive load phases.
- C0 (S1): `loadA` captures 17 into A.
- C1 (S2): `loadB` captures 5; `clearP` sets P=0.
- C2..C6 (S3):
  - C2: P←P+A = 0+17=17; B←4
  - C3: P←34; B←3
  - C4: P←51; B←2
  - C5: P←68; B←1
  - C6: P←85; B←0; `eqZ` becomes 1 for next transition
- C7 (S4): `done=1`; result (85) is stable in `P`.

## Verilog Coding Patterns (width‑parameterized)
```verilog
parameter W = 16;

module pipo1(input  wire        clk,
             input  wire        load,
             input  wire [W-1:0] d,
             output reg  [W-1:0] q);
  always @(posedge clk) if (load) q <= d;
endmodule

module pipo2(input  wire        clk,
             input  wire        load,
             input  wire        clr,
             input  wire [W-1:0] d,
             output reg  [W-1:0] q);
  always @(posedge clk) begin
    if (clr)      q <= {W{1'b0}};
    else if (load) q <= d;
  end
endmodule

module counter(input  wire        clk,
               input  wire        load,
               input  wire        dec,
               input  wire [W-1:0] d,
               output reg  [W-1:0] q);
  always @(posedge clk) begin
    if (load) q <= d;           // load has priority
    else if (dec) q <= q - 1'b1;
  end
endmodule

module adder(input  wire [W-1:0] a,
             input  wire [W-1:0] b,
             output wire [W-1:0] z);
  assign z = a + b;
endmodule

module eq_zero(input  wire [W-1:0] data,
               output wire         eqZ);
  assign eqZ = ~|data; // 1 when data == 0
endmodule
```

### Datapath Top (structural skeleton)
```verilog
module multiplier_datapath(
  input  wire        clk,
  input  wire        loadA, loadB, loadP, clearP, decB,
  input  wire [W-1:0] data_in,
  output wire        eqZ,
  output wire [W-1:0] P_out
);
  wire [W-1:0] x, y, z, bus, B_out;
  assign bus = data_in;

  pipo1 A(.clk(clk), .load(loadA), .d(bus), .q(x));
  pipo2 P(.clk(clk), .load(loadP), .clr(clearP), .d(z), .q(y));
  counter B(.clk(clk), .load(loadB), .dec(decB), .d(bus), .q(B_out));
  adder ADD(.a(x), .b(y), .z(z));
  eq_zero CMP(.data(B_out), .eqZ(eqZ));

  assign P_out = y; // expose product if desired
endmodule
```

### Controller (Moore FSM outline)
```verilog
module controller(
  input  wire clk, start, eqZ,
  output reg  loadA, loadB, loadP, clearP, decB,
  output reg  done
);
  typedef enum reg [2:0] {S0, S1, S2, S3, S4} state_t; // if SystemVerilog
  state_t s, ns;

  // state register
  always @(posedge clk) s <= ns;

  // next-state logic
  always @* begin
    ns = s;
    case (s)
      S0: ns = start ? S1 : S0;
      S1: ns = S2;
      S2: ns = S3;
      S3: ns = eqZ ? S4 : S3;
      S4: ns = S4; // hold; policy could return to S0
      default: ns = S0;
    endcase
  end

  // output decode (Moore)
  always @* begin
    {loadA, loadB, loadP, clearP, decB, done} = 6'b0;
    case (s)
      S1: loadA  = 1'b1;
      S2: begin loadB = 1'b1; clearP = 1'b1; end
      S3: begin loadP = 1'b1; decB   = 1'b1; end
      S4: done   = 1'b1;
    endcase
  end
endmodule
```

### Integration Top (optional)
```verilog
module multiplier_top #(parameter W=16) (
  input  wire        clk,
  input  wire        start,
  input  wire [W-1:0] data_in,
  output wire [W-1:0] product,
  output wire        done
);
  wire loadA, loadB, loadP, clearP, decB, eqZ;
  multiplier_datapath #(.W(W)) dp(
    .clk(clk), .loadA(loadA), .loadB(loadB), .loadP(loadP), .clearP(clearP), .decB(decB),
    .data_in(data_in), .eqZ(eqZ), .P_out(product)
  );
  controller ctl(
    .clk(clk), .start(start), .eqZ(eqZ),
    .loadA(loadA), .loadB(loadB), .loadP(loadP), .clearP(clearP), .decB(decB), .done(done)
  );
endmodule
```

## Testbench Essentials (as in lecture)
- Clock generation: `always #5 clk = ~clk;`
- Start pulse: assert near a non-edge time (e.g., `t=3`) so the next rising edge sees it.
- Apply inputs: write `data_in=17` then later `data_in=5` to match the `loadA`/`loadB` windows.
- Observation: product resides in `P`; can print `dp.P_out` or hierarchical `dp.y`.
- Expected trace for (17,5): `P = 17, 34, 51, 68, 85`, `B_out = 4,3,2,1,0`, then `done=1`.

Example scaffold
```verilog
initial begin
  clk = 0; start = 0; data_in = '0;
  repeat (2) @(posedge clk);
  #3 start = 1; #2 start = 0; // short pulse before next edge

  // align with S1 and S2 load windows
  #12 data_in = 16'd17; // for A
  #10 data_in = 16'd5;  // for B
end

always #5 clk = ~clk;
```

## Robustness and Edge Cases
- Initial B=0: handle early termination.
  - Option A: guard in `S2` — if `eqZ` already 1 after loading B, skip loop and go to `S4`.
  - Option B: add `S2a` check state; small FSM tweak for clarity.
- Reset strategy: prefer synchronous clears; define power‑on behavior; avoid async glitches.
- Width/overflow: for unsigned P, `W` bits suffice only if `B` fits; otherwise consider larger accumulator width or saturation.
- Signed support: define two’s‑complement handling; repeated addition works, but performance poor; prefer Booth/shift‑add.
- Priority of controls: ensure `load` dominates `dec` to avoid off‑by‑one hazards on B.
- Latch avoidance: use `always @*` for combinational blocks and assign all outputs in every path.

## Performance and Microarchitectural Notes
- Iterative multiplier: area‑efficient, latency `≈ B + setup cycles`.
- Critical path: adder + P register input; can improve by letting `loadP` capture adder output; for higher Fmax, pipeline or use carry‑save/Booth.
- Resource sharing: the same adder does all accumulation; controller schedules reuse.
- Throughput: 1 result every `B+3` cycles (non‑overlapped). For multiple transactions, add input buffering and a start/ready queue.

## Variations and Extensions
- Shift‑Add (classical): if `B[0]==1` then `P+=A`; shift `A<<=1`, `B>>=1` each cycle, loop `W` times.
- Booth Multiplication: handles signed values and reduces iterations by encoding runs of ones/zeros.
- Handshake refinement: replace `start/done` with `valid/ready` to support streaming.
- Parameterization: expose `W` and optionally add `UNSIGNED/SIGNED` parameter and saturation option.

## Formal/Assertion Hints (optional)
- Invariant: `P + A*B == A*B0` (where `B0` is the initial B) holds every cycle.
- Progress: `B` is monotonically non‑increasing and eventually reaches zero assuming `decB` in `S3`.
- Simple SystemVerilog assertion sketch:
```systemverilog
// decB only asserted in S3
assert property (@(posedge clk) decB |-> (ctl.s == ctl.S3));
```

## Quick Signal Reference
- Inputs: `clk`, `start`, `data_in[W-1:0]`.
- Controls to datapath: `loadA`, `loadB`, `loadP`, `clearP`, `decB`.
- Status to controller: `eqZ` (1 when B==0).
- Output: `done`; product on `P_out`.

## Common Pitfalls
- Forgetting to clear P before accumulation → leftover value corrupts product.
- Asserting `decB` before `loadB` has taken effect → underflows B.
- Using blocking assignments in sequential always‑@(posedge clk) blocks → ordering‑dependent bugs.
- Implicit latch in controller outputs due to incomplete assignments in the decode block.
- Not qualifying re‑entry from `S4` (define whether a new `start` should be sampled).

## Practice Exercises
- Modify FSM to immediately go to `S4` when `B==0` after load.
- Add an output port `product` mirroring `P_out` and write a self‑checking testbench.
- Parameterize width to `W=8` and simulate multiple test vectors.
- Extend to signed multiplication using Booth encoding or sign‑magnitude handling.

---
End of deep notes for Lecture 25.

## Deeper Dive: Cycle Semantics and Timing
- Register transfer view per loop cycle (state S3):
  - At rising edge t(k): `P <= Z = A + P_prev` (because `loadP=1`); `B <= B_prev - 1` (because `decB=1`).
  - Between t(k) and t(k+1): `eqZ` reflects the newly registered `B`. Hence the controller observes `eqZ` in combinational logic for the next edge.
  - Transition to `S4` happens on t(k+1) if `B` just became 0 at t(k).
- Off‑by‑one intuition: the final accumulation happens in the last cycle where `B_prev==1` (it decrements to 0 on that edge) and then we exit on the following edge.
- Control signal life:
  - `loadA` asserted exactly one S1 cycle; `loadB` and `clearP` exactly one S2 cycle.
  - `loadP` and `decB` asserted every S3 cycle; ensure they are synchronous and glitch‑free.

### Micro‑ops Table Template (for any B)
| Cycle | State | Actions                                | B_before → B_after | Notes                       |
|------:|-------|-----------------------------------------|--------------------|-----------------------------|
|   C0  | S1    | A←data_in                               | N/A                | Capture A                   |
|   C1  | S2    | B←data_in, P←0                          | b0 → b0            | Initialize                  |
| C2..  | S3    | P←P+A; B←B−1                            | b→b−1              | Repeat until B_after==0     |
|   Cend| S4    | done=1                                  | 0 → 0              | Hold result in P            |

## Moore vs Mealy Controller Discussion
- Moore (used above): outputs depend only on state. Pros: robust to input glitches, simpler timing; Cons: may add one‑cycle latency in some handshakes.
- Mealy option here: deassert `loadP/decB` when `eqZ==1` in the same cycle (combinational), potentially avoiding one extra S3 cycle. Risks:
  - Combinational loop hazard if `eqZ` depends on `B` that is modified in the same edge; mitigate by only using registered `B_out` and clean combinational path.
  - Glitch sensitivity—ensure `eqZ` is generated by a single level of logic (`~|B_out`).

## Full‑Precision Variant (2W‑bit Product)
Problem: If A and B are W‑bit, the true mathematical product is up to 2W bits; the basic datapath keeps P at W bits and will overflow.

Design changes:
- Widen `P` and adder to `PW = 2*W`.
- Zero‑extend `A` to `PW` during addition (`{ {W{1'b0}}, A }`).
- Keep `B` at W bits (counter width).

Sketch:
```verilog
parameter W = 16; localparam PW = 2*W;
wire [W-1:0]  A_out, B_out;
wire [PW-1:0] P_out, Z, A_ext = { {W{1'b0}}, A_out };
// P register and adder are PW wide
pipo2 #(.W(PW)) P(.clk(clk), .load(loadP), .clr(clearP), .d(Z), .q(P_out));
adder #(.W(PW))  ADD(.a(A_ext), .b(P_out), .z(Z));
// A remains W wide (pipo1 #(.W(W)))
```

Implications:
- Latency unchanged; area increases in adder and P register.
- Now `product` is exact for unsigned multiplication when iteration completes.

## Reset and Startup Policy
- Synchronous reset recommended for FPGA: add `rst` and include it in every sequential block.
```verilog
always @(posedge clk) begin
  if (rst) q <= '0; else if (load) q <= d;
end
```
- Controller reset: force `s <= S0` and outputs to 0; prevent `start` from being sampled until after at least one rising edge post‑reset.

## Handshake Policies
- Level‑based (current): `start` can be a level; controller samples it in `S0`. Ensure the environment drops `start` before re‑arming.
- Pulse‑based: treat `start` as a one‑cycle pulse; internally synchronize it with edge‑detector.
- Busy/ready interface: expose `busy = (s != S0 && s != S4)` and require `start` only when `busy==0` to avoid re‑starts.

## State Encoding Choices
- Binary (3 bits): minimal registers; slightly more decode logic.
- One‑hot (5 bits): faster decode on FPGAs leveraging LUTs and dedicated carry chains; often improves Fmax at small area cost.
- Gray: rarely useful here.

## Verification: Self‑Checking Testbench
Key goals: randomize inputs, assert functional invariants, and stop when all pass.

Example (SystemVerilog style but can be adapted to Verilog‑2001):
```systemverilog
module tb;
  localparam int W = 8; // small for faster random runs
  logic clk=0, rst=1, start=0; logic [W-1:0] data_in; logic done;
  logic [2*W-1:0] product; // using full-precision variant suggested

  multiplier_top #(.W(W)) dut(.clk(clk), .start(start), .data_in(data_in), .product(product), .done(done));

  always #5 clk = ~clk;

  // simple driver that feeds A then B
  task do_mul(input logic [W-1:0] A, input logic [W-1:0] B);
    // load A
    @(posedge clk); data_in <= A; start <= 1; @(posedge clk); start <= 0;
    // load B on the following cycle
    @(posedge clk); data_in <= B;
    // wait for done
    wait(done);
    @(posedge clk);
    // check
    assert(product == A*B) else $fatal("Mismatch: %0d*%0d got %0d", A,B,product);
  endtask

  initial begin
    repeat (3) @(posedge clk); rst <= 0; // deassert reset
    // directed cases
    do_mul(8'd0, 8'd0);
    do_mul(8'd17, 8'd5);
    do_mul(8'd1,  8'd255);
    // random cases
    foreach (int i[0:99]) do_mul($urandom_range(0,255), $urandom_range(0,255));
    $display("All tests passed");
    $finish;
  end
endmodule
```

Invariant check (works even with W‑bit P):
- Define `B_curr` as the registered B; at any cycle, `P + A*B_curr == A*B_init` should hold. This can be asserted if `A`, `B_init` are captured.

## Common Failure Modes and Fixes (Expanded)
- eqZ latency misunderstanding → extra iteration or missing last add.
  - Fix: remember eqZ is computed from registered B; design transitions accordingly (Moore preferred).
- Simultaneous `loadB` and `decB` due to mis‑decoded state → B underflows.
  - Fix: give `loadB` priority in counter; assert controls in disjoint states only.
- Using blocking assignments (`=`) in sequential always @(posedge clk) for state or regs → simulation order dependency.
  - Fix: always use non‑blocking (`<=`) in sequential logic.
- Incomplete assignment in output decode `always @*` → inferred latches.
  - Fix: set a default for all outputs and override per case.
- P not cleared when chaining operations → previous result contaminates next product.
  - Fix: ensure `clearP` in setup state and define S4→S0 re‑arm behavior.

## Alternative Algorithm: Shift‑Add Multiplier (for completeness)
Reduces iterations from B to W cycles using binary decomposition of B.

Datapath additions:
- Shift register for A (left shift), shift register/counter for B (right shift), accumulator P (wider: 2W recommended), adder P+A.

Per‑cycle actions (for k from 0..W−1):
- If `B[0]==1` then `P += A`.
- `A <<= 1; B >>= 1`.

Controller: initial load, W iterations, then done. Status: iteration counter reaches W.

Pros/Cons:
- Pros: fixed latency W; fewer adds than repeated‑add for large B values of 0/1 density.
- Cons: still sequential; performance slower than fully combinational or Booth/DSP solutions.

## Synthesis Notes (FPGA/ASIC)
- FPGA: adder maps to fast carry chain; one‑hot FSM often yields higher Fmax. Use `(* use_dsp = "no" *)` if you want to force LUT adder (not a DSP multiplier), since we’re not multiplying directly.
- ASIC: balance area/energy by choosing state encoding and adder architecture (ripple/carry‑lookahead). Clock‑gate the datapath in S0/S4 to save power.

## Formal Properties (sketch)
```systemverilog
// Once S3 holds and decB is asserted, B decreases until zero
property monotonic_B; @(posedge clk) disable iff (rst)
  (ctl.s==ctl.S3 && ctl.decB) |=> $past(dp.B_out) > dp.B_out;
endproperty
assert property (monotonic_B);

// Completion: starting from S0 with start, eventually reach S4
property eventual_done; @(posedge clk) disable iff (rst)
  (ctl.s==ctl.S0 && start) |-> s_eventually(ctl.s==ctl.S4);
endproperty
assert property (eventual_done);
```

## Worked End‑to‑End Example (Step‑by‑Step)
Given A=3 (0011), B=4 (0100), W=4, P width W (for illustration only):
- S1: A←3
- S2: B←4, P←0
- S3 cycles:
  - c1: P←0+3=3, B:4→3
  - c2: P←3+3=6, B:3→2
  - c3: P←6+3=9, B:2→1
  - c4: P←9+3=12, B:1→0, eqZ=1 next cycle
- S4: done=1, P=12 (=3×4). With 2W‑bit P this remains exact; with W‑bit P overflow can occur.

## Mapping the Algorithm to Micro‑instructions
- μ‑op set
  - `LD A, data_in`
  - `LD B, data_in`
  - `CLR P`
  - `ADD P, A` (P←P+A)
  - `DEC B`
  - `BRZ B, done`
- Microprogram (straight‑line with loop): `LD A; LD B; CLR P; loop: ADD P,A; DEC B; BRZ B, done; GOTO loop; done: HALT`.

## Portability Notes
- Pure Verilog‑2001 version: replace typedef enum with `parameter` state encodings and 2 always blocks (state register + next‑state/output logic).
- SystemVerilog advantages: strong typing for states/enums, packed structs for control bundles, assertions for correctness.

## Coverage Ideas
- Functional coverage points: B=0, B=1, max B, random B; A=0, max A; combinations that cause overflow in W‑bit P design.
- FSM arc coverage: each transition taken at least once; S3 self‑loop count spans small/large B.

## Practical Integration Tips
- Synchronize `start` from external domains with 2‑flop synchronizer to avoid metastability if crossing clock domains.
- Document contract: `start` sampled only in S0; `done` remains high in S4 until a new transaction (or add explicit `ack`).
- Expose `busy` to upstream logic to prevent overlapping operations.
