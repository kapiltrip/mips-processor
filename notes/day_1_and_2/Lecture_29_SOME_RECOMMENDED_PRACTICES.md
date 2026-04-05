# Lecture 29 — SOME RECOMMENDED PRACTICES

Deep notes capturing common industry HDL guidelines: naming, structure, comments, coding style, partitioning, synthesis‑safe patterns, and checklists. Use these to write reusable, maintainable, synthesis‑friendly Verilog.

## Objectives
- Standardize filenames, identifiers, and signal conventions for clarity at scale.
- Adopt formatting and commenting practices that enable reuse and long‑term maintenance.
- Partition designs to minimize coupling, clarify clocking, and reduce bugs.
- Apply coding patterns that prevent latches and simulation/synthesis mismatches.

## Naming Conventions
- Files
  - Extension: use `.v` (or `.sv` for SystemVerilog) consistently.
  - One design unit (module/interface/package) per file. Filename should match top‑level module inside.
- Identifiers
  - Allowed characters: letters, digits, underscore. Start with a letter; avoid leading underscore.
  - Case policy: treat names as case‑insensitive for uniqueness (even though Verilog is case‑sensitive). Don’t create both `sum` and `Sum`.
  - Constants/parameters/macros: ALL_CAPS with underscores, e.g., `DATA_WIDTH`, `PI`.
  - Signals/variables: lowercase with underscores, e.g., `load_en`, `busy_flag`.
  - Active‑low signals: suffix `_b`, e.g., `rst_b`, `clear_b`.
  - Clocks (and gated/derived clocks): suffix `_clk`, e.g., `bus_clk`, `pix_clk`. Be explicit for gated clocks.
  - Bundle only related fields into buses. Example: instruction word bundling opcode/regs/operands is valid; do not bundle unrelated signals.

Example of meaningful bundling
```verilog
wire [5:0]  opcode;
wire [5:0]  regs;
wire [15:0] operand;
wire [27:0] instruction = {opcode, regs, operand};
```

## Comments and Headers
- Every file must begin with a header containing at least:
  - File name; brief purpose; author/contact; version/history; top‑level construct name; parameter descriptions; clock/reset scheme; notes on critical timing paths.
  - Keep the filename in the header to catch accidental renames.
- Prefer single‑line comments `//` over block `/* ... */` comments for readability and tooling simplicity.
- Document intent near code (why), not just mechanics (what). Avoid stale comments by keeping them short and specific.
- Limit lines to ~80 characters; wrap as needed for readability.

Header template
```text
// File: counter16.v
// Type: module
// Author: Your Name <email@domain>
// Purpose: 16-bit boundary counter with sync clear, enable
// Clocks/Resets: clk (posedge), rst (sync active-high)
// Notes: Critical path = adder + register setup; keep enable fanout low.
// Rev: v1.2 (2025-11-07) — Fix enable polarity and add comments
```

## Formatting and Style
- Indentation: 2–4 spaces; no tabs (tabs render inconsistently across tools).
- One statement per line. Don’t cram multiple statements onto one line.
- Port list formatting: one port per line for clarity; group by direction and purpose.
- Align named port connections; prefer named association over positional.
- Use whitespace to group related logic; keep blocks small and focused.

Port list style
```verilog
module my_block (
  input  wire        clk,
  input  wire        rst,
  input  wire [7:0]  a,
  input  wire [7:0]  b,
  output wire [7:0]  y
);
```

Instantiation style (named)
```verilog
my_block u_my_block (
  .clk (clk),
  .rst (rst),
  .a   (a_i),
  .b   (b_i),
  .y   (y_o)
);
```

## Module Partitioning
- Decompose complex designs into smaller modules and integrate via a top‑level.
- Aim to minimize interface signals across partition boundaries (fewer wires → less coupling).
- Keep clock generation/gating in a dedicated module; avoid deriving clocks deep inside logic.
- Separate clock domains into distinct modules/blocks; clearly document domain crossings and synchronizers.
- Don’t mix asynchronous feedback logic with synchronous FSMs in the same block; isolate asynchronous portions.
- Functions/tasks/procedures must only access signals passed as parameters; avoid hierarchical side‑effects.

Partition quality heuristic
- Prefer partitions that minimize inter‑module signals and maximize cohesion (most related functionality lives together).

## Coding Techniques (Do/Don’t)
- Conditions must be 1‑bit expressions
  - Do: `if (status != 2'b00)` or `if (bus > 0)`. Avoid `if (status)` when `status` is multi‑bit.
- Never assign `X` in RTL intended for synthesis; use reset to drive known values.
- Size matching
  - Match widths on both sides of assignments; be explicit in concatenations/casts to avoid silent truncation/extension.
- Parentheses in complex expressions to clarify precedence.
- Avoid inferring latches
  - Give defaults in `always @*` and cover all `case` items with a `default`.
- Blocking vs non‑blocking
  - Combinational: blocking `=` inside `always @*`.
  - Sequential: non‑blocking `<=` inside `always @(posedge clk ...)`.
- One clock per always block; choose a single edge (usually posedge).
- Avoid `inout` internally; at top level only (IO pads). For FPGAs, avoid internal tri‑states—use muxes.
- Prefer `case` (with default) or SystemVerilog `unique case` where appropriate; avoid `casex`/`casez` unless you control X/Z semantics.
- Use parameters/localparams for constants, widths, and state encodings.

## Synthesis Techniques and Constraints
- Combinational blocks
  - Use `always @*`; assign all outputs along all paths; no delays/waits.
  - Complete sensitivity (implicit via `@*`).
- Sequential blocks
  - Non‑blocking assignments; consistent reset style; one driver per reg.
- No expressions in module port connections; connect named nets/regs only.
- Avoid user‑defined sequential primitives (UDP); even combinational UDPs may be tool‑dependent.
- For edge‑sensitive blocks (posedge/negedge), use only non‑blocking assignments to sequential regs.
- Declare internal wires/regs after IO port declarations; group logically.
- State encoding with parameters/localparams; keep an explicit reset state.

## Safe Templates (Copy/Paste)
1) Synchronous register with enable and sync reset
```verilog
always @(posedge clk) begin
  if (rst) q <= '0;
  else if (en) q <= d;
end
```
2) Combinational block with defaults (no latches)
```verilog
always @* begin
  y = '0; // default
  if (sel) y = a; else y = b;
end
```
3) Two‑process FSM
```verilog
// state register
always @(posedge clk) if (rst) s <= S0; else s <= ns;
// next-state + outputs
always @* begin
  ns = s; outputs = '0;
  case (s)
    S0: if (start) ns = S1;
    S1: begin outputs.do_load = 1; ns = S2; end
    S2: begin outputs.do_calc = 1; ns = done ? S3 : S2; end
    S3: outputs.done = 1;
    default: ns = S0;
  endcase
end
```

## Examples: Good vs Risky
- Risky multi‑bit condition
```verilog
if (status) y = 1'b1; // BAD: status is multi-bit; synthesis may treat nonzero as true, but style is discouraged
```
- Preferred
```verilog
if (status != 2'b00) y = 1'b1; // clearly 1-bit boolean
```
- Risky width mismatch
```verilog
reg [9:0] b; reg [5:0] a; b = a; // silent zero-extend; be explicit
```
- Preferred
```verilog
reg [9:0] b; reg [5:0] a; b = {4'b0000, a};
```

## Checklists
Pre‑code
- Define clock/reset policy; choose widths/parameters; sketch module boundaries; plan CDC.

Style sanity
- Filenames end with `.v`/`.sv`; one module per file; header present.
- Ports one per line; named associations; indentation with spaces; < 80 cols.

Combinational blocks
- Use `always @*`; defaults provided; `case` has `default`; no latches inferred.

Sequential blocks
- Non‑blocking `<=`; one clock edge; reset value defined; one driver per reg.

Synthesis readiness
- No `#` delays, `wait`, `fork/join`, `initial` (unless tool/tech permits).
- Loops bounded by compile‑time constants or `generate`.
- No internal tri‑states; no UDPs; widths match; explicit casts/concats.

Documentation
- Comment intent; document clock domains and critical paths; note assumptions and TODOs.

## Example: Headered Counter Module (Style Demo)
```verilog
// File: boundary_counter16.v
// Type: module
// Author: A. Designer <a.designer@example.com>
// Purpose: 16-bit boundary counter with enable and wrap flag
// Clocks/Resets: clk (posedge), rst (sync active-high)
// Notes: Critical path = adder + compare

module boundary_counter16 (
  input  wire       clk,
  input  wire       rst,
  input  wire       en,
  input  wire [15:0] limit,
  output reg  [15:0] count,
  output reg        wrapped
);
  always @(posedge clk) begin
    if (rst) begin
      count   <= 16'd0;
      wrapped <= 1'b0;
    end else if (en) begin
      if (count == limit) begin
        count   <= 16'd0;
        wrapped <= 1'b1;
      end else begin
        count   <= count + 16'd1;
        wrapped <= 1'b0;
      end
    end
  end
endmodule
```

## Why This Matters (Reuse & Maintainability)
- Well‑structured, documented RTL is easier to verify, integrate, and reuse across projects.
- Consistent styles reduce onboarding time and review friction; they also catch bugs earlier (e.g., latches, width mismatches, CDC mistakes).

---
End of deep notes for Lecture 29.

