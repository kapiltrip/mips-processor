# Lecture 26 — DATAPATH AND CONTROLLER DESIGN (PART 2)

Deep notes distilled from the provided transcript. Focus: alternate FSM coding style and a full datapath/controller design for GCD using repeated subtraction.

## Objectives
- Reinforce the datapath/controller methodology with a nontrivial loop (GCD).
- Compare two controller coding styles and motivate the “state register + combinational next‑state/outputs” approach.
- Build a clean, testable RTL architecture and verify on representative cases.

## Recap of Prior Style vs. Recommended Style
- Prior (used in the earlier lecture’s controller):
  - One clocked `always @(posedge clk)` both computed next state and assigned it to the state register (state computation and update in one block).
  - A second `always @*` generated datapath control outputs using blocking assignments.
- Recommended style (clean two‑process FSM):
  - `always @(posedge clk)`: state register only — `state <= next_state;` (non‑blocking).
  - `always @*`: purely combinational next‑state and output logic — compute `next_state` and drive all outputs with defaults + case overrides (blocking allowed).
- Benefits: clearer timing, no accidental sequential behavior in next‑state logic, easier formal/CDC analysis, fewer simulation mismatches.

## Problem: GCD via Repeated Subtraction
- Definition: `gcd(a,b)` = largest integer dividing both `a` and `b`.
- Simple algorithm (unsigned, nonzero inputs assumed):
  1) If `a == b`, done → result is `a` (or `b`).
  2) If `a > b`, set `a = a − b` and repeat.
  3) If `a < b`, set `b = b − a` and repeat.
- Example (26, 65) → 13:
  - 65−26=39; 39−26=13; 26−13=13 → equal → 13.
- Example (143, 78) → 13:
  - 143−78=65; 78−65=13; 65−13=52; 52−13=39; 39−13=26; 26−13=13 → equal → 13.

## Datapath Microarchitecture
- Storage: two PIPO registers `A` and `B` (width `W=16` in examples).
- Functional: one subtractor; one comparator for `lt`, `gt`, `eq` flags.
- Routing: three 2:1 multiplexers.
  - `MUX_X`: chooses first subtractor input `X` from `{A_out, B_out}` (select `sel1`).
  - `MUX_Y`: chooses second subtractor input `Y` from `{A_out, B_out}` (select `sel2`).
  - `MUX_bus`: chooses write‑back bus from `{data_in, sub_out}` (select `sel_in`).
- Register write enables: `loadA`, `loadB`.
- Status: `lt` (A<B), `gt` (A>B), `eq` (A==B) from comparator.
- External interface: `clk`, `start`, `done`, `data_in[W-1:0]`.

Signal summary
- Controls to datapath: `loadA`, `loadB`, `sel1`, `sel2`, `sel_in`.
- Status to controller: `lt`, `gt`, `eq`.
- Internal wires: `A_out`, `B_out`, `X`, `Y`, `sub_out`, `bus`.

Datapath behavior by operation
- Load A: `sel_in=data_in`, `loadA=1`.
- Load B: `sel_in=data_in`, `loadB=1`.
- `B := B − A`: set `sel1=B`, `sel2=A`, `sel_in=sub_out`, `loadB=1`.
- `A := A − B`: set `sel1=A`, `sel2=B`, `sel_in=sub_out`, `loadA=1`.

## Controller FSM (Concept and Transitions)
- States (6): `S0` (Idle), `S1` (Load A), `S2` (Load B/Compare), `S3` (B:=B−A), `S4` (A:=A−B), `S5` (Done).

State transitions
- `S0 → S1` when `start` asserted.
- `S1 → S2` next clock.
- `S2`: if `eq` → `S5`; else if `lt` (A<B) → `S3`; else (`gt`) → `S4`.
- `S3` (after subtract B:=B−A): re‑compare next cycle → `S3` (if still `lt`), `S4` (if now `gt`), or `S5` (if `eq`).
- `S4` (after subtract A:=A−B): similarly loop among `S3/S4/S5` based on new flags.
- `S5`: hold done high; wait for external clear policy (either stay or reset via separate control).

Output decode (Moore style)
- `S0`: all controls 0; `done=0`.
- `S1`: `loadA=1; sel_in=data_in`.
- `S2`: `loadB=1; sel_in=data_in`.
- `S3`: `sel1=B; sel2=A; sel_in=sub_out; loadB=1`.
- `S4`: `sel1=A; sel2=B; sel_in=sub_out; loadA=1`.
- `S5`: `done=1` (others 0).

Timing note
- Comparator uses registered `A_out` and `B_out`. Subtractions update a register on the clock edge; flags reflect the new values in the following cycle (clean Moore timing, no combinational feedback).

## Verilog RTL — Modules (width‑parameterized)
```verilog
// Two-to-one mux for W-bit vectors
module mux2 #(parameter W=16)(input  wire [W-1:0] n0,
                              input  wire [W-1:0] n1,
                              input  wire         sel,
                              output wire [W-1:0] y);
  assign y = sel ? n1 : n0;
endmodule

// Parallel-in/parallel-out register with load
module pipo #(parameter W=16)(input  wire         clk,
                              input  wire         load,
                              input  wire [W-1:0] d,
                              output reg  [W-1:0] q);
  always @(posedge clk) if (load) q <= d;
endmodule

// Subtractor (combinational)
module sub #(parameter W=16)(input  wire [W-1:0] a,
                             input  wire [W-1:0] b,
                             output wire [W-1:0] z);
  assign z = a - b;
endmodule

// Comparator producing lt/gt/eq
module cmp #(parameter W=16)(input  wire [W-1:0] a,
                             input  wire [W-1:0] b,
                             output wire lt, gt, eq);
  assign lt = (a <  b);
  assign gt = (a >  b);
  assign eq = (a == b);
endmodule
```

### Datapath Top (structural)
```verilog
module gcd_datapath #(parameter W=16)(
  input  wire         clk,
  input  wire         loadA, loadB,
  input  wire         sel1, sel2, sel_in, // 0: A/n0, 1: B/n1 (for sel1/sel2); 0:data_in, 1:sub_out (for sel_in)
  input  wire [W-1:0] data_in,
  output wire         lt, gt, eq,
  output wire [W-1:0] A_out, B_out // for observation
);
  wire [W-1:0] X, Y, sub_out, bus;

  // Registers
  pipo #(.W(W)) A(.clk(clk), .load(loadA), .d(bus), .q(A_out));
  pipo #(.W(W)) B(.clk(clk), .load(loadB), .d(bus), .q(B_out));

  // Muxes for subtractor inputs
  mux2 #(.W(W)) MUX_X(.n0(A_out), .n1(B_out), .sel(sel1), .y(X));
  mux2 #(.W(W)) MUX_Y(.n0(A_out), .n1(B_out), .sel(sel2), .y(Y));

  // Subtractor and comparator
  sub  #(.W(W)) SUB(.a(X), .b(Y), .z(sub_out));
  cmp  #(.W(W)) CMP(.a(A_out), .b(B_out), .lt(lt), .gt(gt), .eq(eq));

  // Writeback bus: 0=data_in, 1=sub_out
  assign bus = sel_in ? sub_out : data_in;
endmodule
```

### Controller — Style A (original single-clocked next-state calc + output block)
```verilog
module gcd_controller_A(
  input  wire clk, start, lt, gt, eq,
  output reg  loadA, loadB, sel1, sel2, sel_in,
  output reg  done
);
  // State encodings (Verilog-2001 parameter style)
  localparam [2:0] S0=3'd0, S1=3'd1, S2=3'd2, S3=3'd3, S4=3'd4, S5=3'd5;
  reg [2:0] s; // current state

  // State transition (next-state computed here and assigned)
  always @(posedge clk) begin
    case (s)
      S0: s <= start ? S1 : S0;
      S1: s <= S2;
      S2: s <= eq ? S5 : (lt ? S3 : S4);
      S3: s <= eq ? S5 : (lt ? S3 : S4);
      S4: s <= eq ? S5 : (lt ? S3 : S4);
      S5: s <= S5;
      default: s <= S0;
    endcase
  end

  // Output decode (Moore)
  always @* begin
    {loadA,loadB,sel1,sel2,sel_in,done} = 6'b0;
    case (s)
      S1: begin loadA=1; sel_in=1'b0; end               // load A from data_in
      S2: begin loadB=1; sel_in=1'b0; end               // load B from data_in
      S3: begin sel1=1; sel2=0; sel_in=1; loadB=1; end  // B := B - A
      S4: begin sel1=0; sel2=1; sel_in=1; loadA=1; end  // A := A - B
      S5: begin done=1; end
    endcase
  end
endmodule
```

### Controller — Style B (recommended two‑process FSM)
```verilog
module gcd_controller_B(
  input  wire clk, start, lt, gt, eq,
  output reg  loadA, loadB, sel1, sel2, sel_in,
  output reg  done
);
  localparam [2:0] S0=3'd0, S1=3'd1, S2=3'd2, S3=3'd3, S4=3'd4, S5=3'd5;
  reg [2:0] s, ns; // state and next-state

  // 1) State register
  always @(posedge clk) s <= ns;

  // 2) Next-state + outputs (combinational)
  always @* begin
    // defaults
    {loadA,loadB,sel1,sel2,sel_in,done} = 6'b0;
    ns = s;
    case (s)
      S0: begin ns = start ? S1 : S0; end
      S1: begin ns = S2; loadA=1; sel_in=1'b0; end
      S2: begin ns = eq ? S5 : (lt ? S3 : S4); loadB=1; sel_in=1'b0; end
      S3: begin ns = eq ? S5 : (lt ? S3 : S4); sel1=1; sel2=0; sel_in=1; loadB=1; end
      S4: begin ns = eq ? S5 : (lt ? S3 : S4); sel1=0; sel2=1; sel_in=1; loadA=1; end
      S5: begin ns = S5; done=1; end
      default: begin ns = S0; end
    endcase
  end
endmodule
```

### Integration Top
```verilog
module gcd_top #(parameter W=16)(
  input  wire         clk,
  input  wire         start,
  input  wire [W-1:0] data_in,
  output wire [W-1:0] A_out, B_out,
  output wire         done
);
  wire loadA, loadB, sel1, sel2, sel_in, lt, gt, eq;
  gcd_datapath #(.W(W)) dp(
    .clk(clk), .loadA(loadA), .loadB(loadB), .sel1(sel1), .sel2(sel2), .sel_in(sel_in),
    .data_in(data_in), .lt(lt), .gt(gt), .eq(eq), .A_out(A_out), .B_out(B_out)
  );
  gcd_controller_B ctl(
    .clk(clk), .start(start), .lt(lt), .gt(gt), .eq(eq),
    .loadA(loadA), .loadB(loadB), .sel1(sel1), .sel2(sel2), .sel_in(sel_in), .done(done)
  );
endmodule
```

## Testbench Strategy and Expected Trace
- Clock: period 10 (toggle every 5).
- Start: assert at `t=3` to be sampled by next rising edge.
- Stimulus: apply A then B to `data_in` aligned with `S1` then `S2`.
- Monitors: track `A_out`, `B_out`, and `done`; optionally dump VCD.

Directed case (143, 78), W=8/16
- Initial loads: A=143 (0x8F), B=78 (0x4E).
- Iteration sequence (A,B):
  - (143, 78) → A>B → A:=A−B=65
  - (65, 78)  → A<B → B:=B−A=13
  - (65, 13)  → A>B → A:=A−B=52
  - (52, 13)  → A>B → A:=A−B=39
  - (39, 13)  → A>B → A:=A−B=26
  - (26, 13)  → A>B → A:=A−B=13
  - (13, 13)  → eq → done; result = 13 (in both A and B)

Sanity assertions
- A and B remain non‑negative (unsigned arithmetic).
- `A_out==B_out` at `done==1`.
- `lt`, `gt`, `eq` are mutually exclusive and one‑hot per cycle.

## Algorithmic Properties and Invariants
- Invariance: `gcd(A,B)` is unchanged by replacing `(A,B)` with `(A−B,B)` when `A>B`, or `(A,B−A)` when `B>A`.
- Termination: with positive integers, `max(A,B)` strictly decreases on each subtract step; process halts when `A==B`.
- Edge cases:
  - If either input is zero initially: `gcd(A,0)=A` → detect early and go to `S5`.
  - If inputs equal on load: `eq` in `S2` sends directly to `S5`.

## Complexity and Alternatives
- Repeated subtraction worst‑case cycles ≈ `A+B` (slow for large, close values).
- Euclid’s algorithm with modulo: replace subtract loop with `A := A % B` (or `B := B % A`), much faster (O(log min(A,B))).
- Binary GCD (Stein’s algorithm): uses shifts and subtraction; efficient in hardware without division.

Hardware implications
- Modulo requires divider or iterative subtract/shift datapath; binary GCD adds shifters and a factor‑of‑two counter.
- The presented design emphasizes clarity of datapath/control partitioning using only comparator, subtractor, and muxes.

## Robustness, Resets, and Handshake
- Add synchronous `rst` to registers and controller (`s <= S0`).
- Handshake policy: sample `start` only in `S0`; expose `busy = (s!=S0 && s!=S5)`.
- Re‑arm behavior: either hold `S5` until external reset/ack, or auto‑return to `S0` when `start` deasserts.

## Pitfalls and How to Avoid Them
- Missing default assignments in combinational block → inferred latches; always set defaults for outputs and `ns`.
- Using blocking assignments in `@(posedge clk)` sequential logic → ordering issues; use non‑blocking (`<=`).
- Driving `sel_in=sub_out` and `loadA/loadB` for multiple registers in same state inadvertently → ensure only the targeted register is enabled.
- Comparator vs. subtract timing: compute flags from registered values, not from the combinational subtract path.

## Formal and Coverage Suggestions
- Assertions
  - Mutual exclusivity: `assert(!(lt&&gt)); assert(!(lt&&eq)); assert(!(gt&&eq));`
  - Monotonic decrease: when in `S3`, `B_out` decreases; when in `S4`, `A_out` decreases.
  - Liveness: from `S0` with `start`, eventually `S5`.
- Coverage
  - Cover each arc: `S2→S3`, `S2→S4`, `S2→S5`, `S3→S3`, `S4→S4`, `S3→S4`, `S4→S3`.
  - Edge cases: `A==B` initially; `A==0` or `B==0`.

## Micro‑Instruction View
- μ‑ops:
  - `LD A, data_in`; `LD B, data_in`.
  - `CMP A,B` → set `{lt,gt,eq}`.
  - `SUB & WR B := B−A` or `A := A−B` via muxed subtractor and `sel_in=sub_out`.
  - `BRZ eq` → `DONE`.
  - `BR lt` → `SUB B,A`; `BR gt` → `SUB A,B`.

## Synthesis Notes
- FSM encoding: one‑hot may increase Fmax on FPGA; binary is area‑efficient.
- Subtractor uses carry chain; comparator typically maps to LUT logic or DSP comparison if available.
- Register enables (`loadA/loadB`) infer CE pins on FPGA flip‑flops, saving power.

## Extension Exercises
- Add `rst` and `busy`; return to `S0` automatically when `start` reasserts with new inputs.
- Implement binary GCD with shift counters and compare subtract; compare latency.
- Modify datapath to support modulo‑based Euclid with an iterative subtract/restore division micro‑sequence.
- Add a top‑level I/O that exposes the final GCD and a cycle counter for performance measurement.

---
End of deep notes for Lecture 26.

