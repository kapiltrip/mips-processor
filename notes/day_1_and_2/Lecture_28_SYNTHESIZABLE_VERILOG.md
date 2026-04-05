# Lecture 28 — SYNTHESIZABLE VERILOG

Deep notes focused on the synthesizable subset of Verilog: what maps to hardware, what to avoid, recommended coding styles, and practical templates for combinational and sequential logic. Includes pitfalls that pass simulation but fail or mis-map during synthesis.

## Goals
- Understand the difference between simulation semantics and synthesis semantics.
- Learn which Verilog constructs reliably synthesize to hardware and which do not.
- Adopt robust templates for combinational, sequential, and FSM code that avoid latches and timing traps.
- Use functions/tasks appropriately in synthesizable code.

## Big Picture: Simulation vs Synthesis
- Simulation executes a behavioral model (zero or specified delays, X/Z semantics, `$display`), used for functional verification.
- Synthesis elaborates HDL → Boolean logic/registers → maps onto a target technology library (FPGA LUTs/FFs/DSPs/BRAMs or ASIC cells).
- Not everything you can simulate can be synthesized. The “synthesizable subset” excludes timing controls, dynamic processes, certain data types, and data‑dependent structural replication.

## Core Rules — Combinational Logic
- No timing controls or event delays
  - Avoid `#...`, `wait(...)`, `event` triggers. Synthesis ignores them or rejects the design.
- No feedback loops in purely combinational netlists
  - A combinational path from output back to input can oscillate/metastabilize; if you need feedback, use a register (sequential logic).
- Fully specify outputs for all input cases
  - In `if/else` or `case`, every output driven in the block must be assigned on every path. Missing assignments infer latches.
- Complete sensitivity lists
  - Use `always @*` (or SystemVerilog `always_comb`). Manually listing inputs risks omission → latch inference or stale values in sim.
- Blocking assignments in combinational blocks
  - Use `=` (blocking) inside `always @*`. Reserve `<=` for clocked sequential logic.
- Data‑dependent loops are not synthesizable in combinational logic
  - Bounds must be static (compile‑time constants). Use `for` with constant limits or a `generate` block; avoid `while`, `repeat` with variable counts.
- Avoid technology/timing modeling inside RTL
  - No delay `#`, rise/fall constructs, or specify blocks in synthesizable code.
- `case` usage
  - Include `default:` to ensure completeness. Prefer `case` or SystemVerilog `unique/priority case` over `casex/casez` unless you fully understand X/Z don’t‑care implications in synthesis.

## Core Rules — Sequential Logic
- Use explicit edge control for flip‑flops
  - `always @(posedge clk)` (and optional async reset) to infer FFs. Avoid level‑sensitive `always @ (a or b)` for sequential state.
- Non‑blocking assignments for registers
  - Use `<=` inside clocked `always`. Prevents ordering races and matches real flip‑flop behavior.
- One clock per always block; avoid mixed edges
  - Don’t use both `posedge` and `negedge` of the same clock in one register block. Choose a single edge.
- Resets
  - Prefer synchronous reset in FPGAs; async reset only if required. Ensure all stateful regs have a defined reset or safe power‑up value.
- Single driver rule
  - A given `reg/logic` should be driven from exactly one always block.

## Modeling Styles Supported by Synthesis
- Gate netlists with built‑in primitives (and, or, xor, not, nand, nor, xnor, buf)
- Continuous assignments (`assign`) for combinational logic
- Combinational procedural blocks (`always @*`) with blocking assignments
- Sequential procedural blocks (`always @(posedge clk [or posedge rst])`) with non‑blocking assignments
- Functions (combinational only; single return value; no timing)
- Tasks (allowed if they contain no timing/wait/fork; can return multiple outputs via arguments; some tools restrict — prefer functions for pure combinational expressions)
- Parameters/localparams, `generate` with `for` loops and `genvar`

## Constructs to Avoid (Non‑Synthesizable or Risky)
- `initial` (usually not synthesizable in ASIC; some FPGAs allow init of regs/BRAM — tool/tech dependent)
- Delay controls `#`, event controls outside sensitivity lists, `wait`, `fork/join`, `disable`, user‑defined sequential primitives (UDP)
- Data types: `real`, `time`; use `integer`/`reg`/`logic`/packed vectors instead
- Equality with X/Z matching: `===`, `!==` typically not synthesizable; use `==`, `!=` only
- Data‑dependent loops: `while (...)`, `repeat (var)` in synthesizable blocks
- Internal tri‑states on FPGAs: use muxes instead; `inout` permitted at IO pads only (top‑level)

## Preventing Latches — Practical Patterns
1) Default‑then‑override
```verilog
always @* begin
  y = '0;            // default assignment covers all paths
  if (sel) y = a;
end
```
2) Complete `case` with default
```verilog
always @* begin
  unique case (sel)
    2'b00: y = a;
    2'b01: y = b;
    2'b10: y = c;
    default: y = d;  // required
  endcase
end
```
3) All outputs assigned
```verilog
always @* begin
  {y,z} = 0; // both outputs get defaults
  if (take_y) y = a; else z = b;
end
```

## Sensitivity and Assignment Rules (Summary)
- Combinational: `always @*` + blocking `=`.
- Sequential: `always @(posedge clk [or posedge rst])` + non‑blocking `<=`.
- Never mix blocking/non‑blocking on the same signal.

## Using Functions and Tasks in Synthesizable Code
- Functions
  - Single return via function name; no timing; inputs required; declare local temps as `reg`/`logic`.
  - Use inside `assign` or `always @*` for combinational calculations.
```verilog
function [W-1:0] sat_add(input [W-1:0] a,b);
  reg [W:0] s; begin
    s = a + b; sat_add = s[W] ? {W{1'b1}} : s[W-1:0];
  end
endfunction
assign y = sat_add(a,b);
```
- Tasks
  - Multiple outputs possible; keep synthesizable by avoiding `#`, `wait`, event controls. Good for code reuse in large combinational blocks.
```verilog
task add_sub;
  input [W-1:0] a,b; input sub;
  output [W-1:0] z; output c;
  reg [W:0] t; begin t = sub ? (a - b) : (a + b); {c,z} = t; end
endtask
```

## Gate Netlist vs Functional Style
- Gate netlists tie you to explicit primitives; synthesis may remap them to target library equivalents.
- Functional/behavioral descriptions (`assign`, `always @*`) allow the tool to optimize and use hardened blocks (e.g., DSPs for multipliers).

## Loops and Generate
- Combinational loops with static bounds are unrolled by the elaborator
```verilog
// parity example
always @* begin
  parity = 1'b0;
  for (int i=0; i<W; i++) parity = parity ^ data[i];
end
```
- Structural replication: use `generate`
```verilog
genvar i; generate for (i=0;i<N;i=i+1) begin: G
  mycell u(.a(a[i]), .b(b[i]), .y(y[i]));
end endgenerate
```

## Safe Templates
1) Registered pipeline stage
```verilog
always @(posedge clk) begin
  if (rst) q <= '0; else q <= d; // non-blocking
end
```
2) Two‑process FSM (recommended)
```verilog
// state register
always @(posedge clk) if (rst) s <= S0; else s <= ns;
// next-state & outputs
always @* begin
  ns = s; outputs = '0; // defaults
  case (s)
    S0: begin if (start) ns=S1; end
    S1: begin outputs.do_x=1; ns=S2; end
    // ...
    default: ns = S0;
  endcase
end
```
3) Combinational mux
```verilog
always @* begin
  y = in0; // safe default
  if (sel) y = in1;
end
```

## X/Z and Equality
- Simulation lets X/Z propagate and allows `===/!==` to match unknowns.
- Synthesis treats X as “don’t care” during optimization; avoid writing RTL that depends on X‑aware comparisons.
- Prefer explicit resets or initialization via reset, not via `initial` (except where the tool/tech allows it and you accept portability limits).

## Synthesis‑Friendly Operators
- Arithmetic: `+ − *` (multipliers may map to DSPs), `/ %` often expensive or not inferred unless obvious; consider iterative datapaths.
- Bitwise/logical: `& | ^ ~ &~ |~ ^~` supported; reductions likewise.
- Shifts: `<< >> >>>` (arithmetic right `>>>` for signed).
- Concatenation/replication: `{}`, `{N{expr}}` are synthesizable.

## Example Set
1) Full adder, functional
```verilog
module full_adder(input a,b,cin, output sum, cout);
  assign {cout,sum} = a + b + cin;
endmodule
```
2) 2:1 mux, procedural
```verilog
module mux2(input [W-1:0] i0,i1, input sel, output reg [W-1:0] y);
  always @* y = sel ? i1 : i0;
endmodule
```
3) Priority encoder (avoid latches via default)
```verilog
always @* begin
  idx = 3'd0; valid = 1'b0;
  for (int i=7;i>=0;i--) if (in[i]) begin idx=i; valid=1'b1; end
end
```

## Tooling Notes
- Simulation: Icarus Verilog + GTKWave support most constructs (including many non‑synthesizable ones) for verification.
- Synthesis: open‑source Yosys or commercial tools (Synopsys DC, Cadence Genus, Xilinx Vivado, Intel Quartus). Check exact support matrices (e.g., tasks, initial register values, for‑loop limits).
- Tech mapping: the same RTL can synthesize differently across FPGAs/ASICs; avoid relying on unspecified behaviors.

## Quick Reference — Allowed vs Disallowed
- Allowed (commonly): `module/endmodule`, `assign`, `always @*`, `always @(posedge clk)`, built‑in gates, parameters/localparams, `generate/for`, functions, tasks (timing‑free), `if/else`, `case` with default, arithmetic/bitwise ops, concatenation/replication, part‑selects/slices.
- Disallowed or Tool‑Dependent: `initial` (ASIC), delays `#`, `wait`, `fork/join`, `disable`, UDPs (sequential), `real`, `time`, X‑equality `===/!==`, variable‑bound loops, internal tri‑states.

## Pre‑Synthesis Checklist
- Combinational blocks use `always @*` and assign all outputs on all paths (no latches).
- Sequential blocks use `<=` and a single clock edge; reset defined.
- No delays, waits, or event triggers outside sensitivity lists.
- Loops have static, constant bounds or `generate` is used.
- No X‑dependent logic; `case` has a `default:`.
- Each register driven by exactly one always block.
- For FPGAs, avoid internal tri‑states; use muxing.

## Post‑Synthesis Sanity
- Review synthesis warnings about inferred latches, multi‑drivers, unconnected nets, removed logic.
- Inspect the technology schematic: ensure FF counts, DP mapping, and state encodings match expectations.
- Constrain timing (SDC/XDC) and re‑synthesize until clean timing is achieved.

---
End of deep notes for Lecture 28.

