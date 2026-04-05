# Introduction — Pipelined MIPS-like Processor (Verilog)

This project is an educational, “from-the-ground-up” model of a small MIPS-like processor written in Verilog. The goal was not to clone the entire MIPS ISA or to build a production-grade CPU, but to build a *coherent, working microarchitecture* that makes the core ideas of processor design concrete: instruction encoding, datapath construction, control generation, pipelining, and verification. In short, it answers: **how does a 32-bit instruction actually move through hardware and become a register update, a memory access, or a branch?**

At the center of the project is a **5-stage pipelined datapath** (IF -> ID -> EX -> MEM -> WB) implemented with explicit pipeline registers (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`) inside the top module. The pipeline is driven using a **two-phase clocking scheme** (`clock1` and `clock2`) so that adjacent stages operate on alternating edges (IF/EX/WB on `clock1`, ID/MEM on `clock2`). This keeps the design conceptually close to textbook pipeline timing, makes the stage boundaries visible in waveforms, and reduces “read/write in the same instant” ambiguity when learning how a pipeline behaves.

## What I actually built (and why it matters)

The most important deliverable here is not a single file—it’s the set of design decisions that turn “a processor” into real RTL:

- **A clear datapath decomposition**: register file + ALU + memory + PC logic, stitched together by pipeline registers so that multiple instructions are in-flight at once.
- **A minimal control strategy that still scales**: rather than emitting a long list of control wires, the `control_unit` classifies each instruction into a small set of *instruction types* (RR-ALU, RM-ALU, LOAD, STORE, BRANCH, HALT). The top module then derives mux selects and write enables from that type.
- **A consistent instruction format and encoding story**: machine words are not magic constants; the repo includes a `calculation/` companion that shows how each hex instruction word is derived from opcode + register fields + immediates (including two’s-complement negative offsets).
- **Verification artifacts**: the processor is exercised using three targeted testbenches that load programs into memory, run the two-phase clocks, dump waveforms, and validate final register/memory states.

This combination is what makes the project defensible: it demonstrates both implementation skill (RTL that simulates correctly) and engineering discipline (repeatable encoding + observable verification).

## Architecture overview (how instructions flow)

The design lives in `modellingOftheProcessor/mips.v` and is organized around four pipeline register sets:

- **IF/ID** holds the fetched instruction word and the “next PC” (`NPC`).
- **ID/EX** holds decoded state: the instruction, `NPC`, register operands (`A`, `B`), the sign-extended immediate, and the decoded instruction type.
- **EX/MEM** holds ALU output (either arithmetic result or computed address/branch target), the forwarded store value (`B`), the branch condition flag, and the instruction type.
- **MEM/WB** holds the value that will be written back: either ALU output or a loaded memory word (`LMD`).

Even though there are multiple stages, each stage is conceptually simple:

- **Fetch (IF)** reads instruction memory at the current fetch address and increments the PC.
- **Decode (ID)** reads register operands and sign-extends the immediate.
- **Execute (EX)** performs ALU work: arithmetic/logic, effective address calculation, or branch target calculation.
- **Memory (MEM)** reads/writes the unified memory for `LW`/`SW`.
- **Writeback (WB)** writes the final value to the register file (unless it is suppressed by control rules).

The project’s “aha” is that *nothing is implicit*: every time an instruction crosses a stage boundary, it is captured in a pipeline register, which is exactly what makes the pipeline observable and debuggable.

## The supported ISA (small, deliberate, and testable)

The processor implements a compact, MIPS-inspired set of instructions where the **opcode bits `[31:26]` directly select the operation** (there is no separate `funct` field for R-type operations in this educational ISA). The supported operations are:

- **Register-register ALU (RR-ALU):** `ADD`, `SUB`, `AND`, `OR`, `SLT`, `MUL`
- **Register-immediate ALU (RM-ALU):** `ADDI`, `SUBI`, `SLTI`
- **Memory:** `LW`, `SW`
- **Control-flow:** `BEQZ` (branch if register is zero), `BNEQZ` (branch if register is not zero)
- **Stop:** `HLT`

Immediates are **sign-extended** inside the pipeline, so negative offsets (for branches and stores) work naturally when encoded in 16-bit two’s complement form. The memory model is **word-addressed** (PC increments by 1 and the memory array is indexed by word), which keeps the focus on control/datapath behavior instead of byte-addressing details.

## Control philosophy (simple signals, strong structure)

The `modellingOftheProcessor/control_unit.v` module turns `opcode -> instr_type`. That type is then used to:

- Select ALU inputs (e.g., branch uses `NPC` as an ALU input so the ALU can compute target = `NPC + imm`).
- Decide whether an instruction should write a register, write memory, or do neither.
- Decide what register should be written (`rd` for RR-ALU vs `rt` for immediates/loads) and what data should be written (ALU result vs loaded word).

This structure is important because it mirrors a real CPU design flow:

1. Identify instruction *classes* with similar control needs.
2. Build a datapath that can support those classes.
3. Keep the control as small and clean as possible while still being correct.

In an interview/viva, this is a key design point: the project shows you can reduce a complex control problem to a disciplined set of categories and derived behavior.

## Pipelining realities: hazards, bubbles, and branch redirection

This CPU is intentionally minimal: it does **not** implement full hazard detection, stalling, or forwarding. That choice is not a weakness—it is an explicit boundary that keeps the project focused and makes pipeline timing visible. The consequence is that **read-after-write (RAW) dependencies must be padded** in software/test programs.

To do this, the test programs insert safe “NOP-like” bubbles using a self-OR:

- `OR Rx, Rx, Rx` leaves the architectural state unchanged but consumes a pipeline slot.

This is documented directly in `calculation/README.md` and used throughout the testbenches.

Branches are handled by:

- Computing the branch condition (`rs == 0`) and target (`NPC + imm`) in the pipeline.
- Redirecting instruction fetch when the branch is taken.
- Suppressing side effects from the wrong-path instruction using a `taken_branch` gating approach (so wrong-path register writes, stores, and even an accidental `HLT` do not “commit”).

The result is a pipeline that behaves predictably in simulation and is easy to reason about at the stage level.

## How I verified it (evidence, not assumptions)

Verification is done through three concrete programs, each with a dedicated testbench in `modellingOftheProcessor/`:

- `tb_add_three_numbers.v`: immediate loads + dependent adds (tests RR-ALU + bubble placement).
- `tb_factorial.v`: a loop using `LW`, `MUL`, `SUBI`, `BNEQZ`, and `SW` (tests control flow + negative offsets + memory).
- `tb_memory_word.v`: `LW` -> `ADDI` -> `SW` (tests basic memory and writeback behavior).

Each testbench:

- Initializes registers to known values for visibility.
- Loads machine words directly into the memory array.
- Runs a two-phase clock for enough cycles to complete the program.
- Dumps a `.vcd` waveform so pipeline register contents, ALU activity, and control gating can be inspected visually.

Separately, the `calculation/` folder provides the "paper trail" of instruction encoding and explains why bubbles are inserted where they are-making the simulations reproducible and explainable.

## How to run the simulations (quick demo commands)

From `modellingOftheProcessor/` (requires Icarus Verilog: `iverilog` + `vvp`):

- Add-three-numbers: `iverilog -g2012 -s tb_add_three_numbers -o sim_add *.v` then `vvp sim_add` (expected: `R5 = 55`)
- Memory-word demo: `iverilog -g2012 -s tb_memory_word -o sim_mem *.v` then `vvp sim_mem` (expected: `Mem[121] = 130`)
- Factorial: `iverilog -g2012 -s tb_factorial -o sim_fact *.v` then `vvp sim_fact` (expected: `Mem[198] = 5040` when `Mem[200] = 7`)

Each run writes a `.vcd` waveform (`tb_*.vcd`) for inspection in GTKWave.

## Limitations (and how I would extend it)

This design is intentionally scoped, so the limitations are clear and educational:

- No forwarding, stalling, or automated hazard detection (dependencies are padded with NOPs).
- Word-addressed unified memory (no byte addressing or separate I/D memories).
- Simplified instruction encoding (opcode directly selects ALU operation).

Natural extensions (and a great “future work” story) include adding forwarding paths, a hazard unit to insert stalls automatically, a cleaner branch flush mechanism, byte addressing with alignment rules, and broader ISA coverage while moving closer to standard MIPS encoding.

## How to present what I did (a practical talk-track)

If I had 2–3 minutes to explain this project, I would structure it like this:

1. **Goal:** “I built a pipelined MIPS-like CPU in Verilog to learn datapath + control + pipeline timing.”
2. **What’s implemented:** “A 5-stage pipeline with regfile, ALU, unified memory, a small ISA (ALU ops, immediates, load/store, branches, halt).”
3. **Key design choices:** “Two-phase clocks for clean stage separation; instruction-type based control; word-addressed memory for simplicity.”
4. **Proof it works:** “Three programs (add, memory, factorial loop) + VCD waveforms + documented instruction encodings in `calculation/`.”
5. **What I’d improve next:** “Forwarding/stalls, hazard unit, and more ISA coverage.”
