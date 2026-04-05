# Viva / Defense Q&A — Pipelined MIPS-like Processor (Verilog)

Use this as a “spoken script” bank. The best way to answer is:
**(1) state the idea**, **(2) point to where it exists in the design**, **(3) mention one limitation/future upgrade**.

---

## 1) High-level framing

**Q1. What did you build in this project, in one sentence?**  
**A.** I built a simplified, pipelined 5-stage MIPS-like processor in Verilog with a small custom ISA (ALU ops, immediates, load/store, branches, halt) and verified it using three program testbenches plus waveform dumps.

**Q2. What is “MIPS-like” about it, and what is intentionally different?**  
**A.** It is MIPS-like in that it uses a 32-bit instruction word, a register file, an ALU, `LW/SW`, and simple conditional branches (`BEQZ/BNEQZ`) with sign-extended immediates. It is intentionally different because R-type operations are not selected by a `funct` field; instead the opcode directly identifies operations like `ADD/SUB/OR/MUL`. Also, PC and memory are word-addressed in this model (PC increments by 1).

**Q3. What is the key learning outcome this project demonstrates?**  
**A.** Converting ISA intent into a working microarchitecture: how instruction fields drive control, how stage registers make pipelining real, how timing affects correctness, and how to validate behavior with directed programs and waveforms.

**Q4. What are the main modules/components?**  
**A.** A top pipeline (`modellingOftheProcessor/mips.v`), an ALU (`alu.v`), a register file (`regfile.v`), a control classifier (`control_unit.v`), and a unified instruction/data memory model (`memory_interface.v`), plus testbenches.

**Q5. Why did you implement it as a pipeline rather than a single-cycle CPU?**  
**A.** A pipeline makes instruction overlap visible and teaches real CPU concerns (stage boundaries, RAW hazards, branch redirection). It’s also closer to how real processors are structured, even if simplified.

---

## 2) ISA, formats, and encoding

**Q6. What instructions are supported?**  
**A.** Register-register ALU: `ADD, SUB, AND, OR, SLT, MUL`; register-immediate: `ADDI, SUBI, SLTI`; memory: `LW, SW`; branches: `BEQZ, BNEQZ`; and `HLT`.

**Q7. What are the instruction formats?**  
**A.**
- RR-ALU: `opcode[31:26] | rs[25:21] | rt[20:16] | rd[15:11] | zeros[10:0]`  
- Immediate/Load/Store: `opcode[31:26] | rs[25:21] | rt[20:16] | imm[15:0]`  
- Branch: `opcode[31:26] | rs[25:21] | (unused/0)[20:16] | offset[15:0]`

**Q8. Where is the immediate sign extension done?**  
**A.** In the decode stage pipeline register capture: `ID_EX_IMM <= {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]}` inside `mips.v`. That makes negative offsets work naturally.

**Q9. How do you compute branch targets?**  
**A.** For branch-type instructions, the ALU is reused to compute `target = NPC + imm`. In `mips.v`, `alu_a` is set to `ID_EX_NPC` for branches and the ALU operation for `BEQZ/BNEQZ` is defined as addition.

**Q10. Why does PC increment by 1 instead of 4?**  
**A.** The memory is modeled as word-addressed (`mem[index]` is a full 32-bit word), so advancing to the next instruction means `PC = PC + 1`. This avoids byte-addressing complexity while learning the pipeline/control behavior.

**Q11. How are your hex instruction words generated?**  
**A.** The repo includes `calculation/` notes that show opcode lookup, field placement, two’s complement for negatives, and binary-to-hex conversion step-by-step. This makes the programs reproducible rather than “magic constants”.

**Q12. How do you handle negative branch offsets and negative store offsets?**  
**A.** They are encoded as 16-bit two’s complement immediates. The CPU sign-extends them to 32-bit in decode, then uses the ALU to add base + offset.

---

## 3) Datapath and the 5-stage pipeline

**Q13. What are the five pipeline stages and what happens in each?**  
**A.**
- **IF:** select fetch address, read instruction memory, compute `NPC = PC+1`, update `PC`.  
- **ID:** decode opcode to type, read register operands, sign-extend immediate.  
- **EX:** ALU executes arithmetic/logic or address/target calculation; branch condition is evaluated.  
- **MEM:** load reads memory into LMD, store writes memory.  
- **WB:** write results to register file; halt is committed.

**Q14. What pipeline registers exist and what do they store?**  
**A.** `IF/ID` stores instruction + NPC; `ID/EX` stores instruction + NPC + A/B + IMM + type; `EX/MEM` stores instruction + ALUOut + B + cond + type; `MEM/WB` stores instruction + ALUOut + LMD + type.

**Q15. Why do you carry the instruction word through the pipeline registers?**  
**A.** It makes debugging straightforward (you can see exactly which instruction is in which stage), and it provides access to fields (e.g., destination register bits) in later stages like WB.

**Q16. What does `ID_EX_type` represent?**  
**A.** It is a compact classification of instruction behavior (RR-ALU, RM-ALU, LOAD, STORE, BRANCH, HALT). It is the “summary control state” that drives muxing and enables downstream.

**Q17. How do you select the ALU operands?**  
**A.** In `mips.v`:  
- `alu_a` is `ID_EX_A` normally, but for branches it becomes `ID_EX_NPC`.  
- `alu_b` is `ID_EX_B` only for RR-ALU; otherwise it is the immediate (`ID_EX_IMM`).  
This matches the needs of RR ops, immediates, address calc, and branch target calc with one ALU.

**Q18. Where is the destination register chosen?**  
**A.** In WB combinational logic: `rd` (`[15:11]`) is used for RR-ALU; `rt` (`[20:16]`) is used for RM-ALU and LOAD. This mirrors MIPS conventions.

**Q19. What is written back for each instruction class?**  
**A.**
- RR-ALU/RM-ALU: ALU result (`MEM_WB_ALUOut`)  
- LOAD: loaded word (`MEM_WB_LMD`)  
Stores and branches don’t write registers.

---

## 4) Control design (and why it’s structured this way)

**Q20. What does the control unit output, exactly? Why not output many signals?**  
**A.** The control unit outputs only `instr_type` (3 bits). The “many signals” are derived from the type in the top module (ALU mux selection, reg write enable, mem write enable, writeback select). This keeps the control simple and makes the datapath behavior the focus.

**Q21. How does the control unit map opcodes to types?**  
**A.** `control_unit.v` uses a `case` on `opcode` and groups opcodes by behavior: ALU register-register -> RR_ALU, ALU immediate -> RM_ALU, `LW` -> LOAD, `SW` -> STORE, branches -> BRANCH, `HLT` -> HALT.

**Q22. What happens on an unknown opcode?**  
**A.** The control defaults to `HALT`. This is a defensive choice for simulation: invalid programs stop rather than causing hard-to-debug behavior.

**Q23. Why does the ALU use the opcode directly rather than a separate ALUControl signal?**  
**A.** Because the ISA is simplified so that the opcode uniquely identifies the operation. In a more standard design, you’d decode opcode + funct into a smaller ALUControl bus.

---

## 5) Two-phase clocks: timing and correctness

**Q24. Why do you have two clocks (`clock1`, `clock2`) instead of one?**  
**A.** It’s an educational timing model where alternating stages update on alternating edges (IF/EX/WB on `clock1`, ID/MEM on `clock2`). It makes stage separation very clear and avoids “same-edge” read/write ambiguity when learning.

**Q25. Where are these two clocks actually used?**  
**A.** In `mips.v`, IF/EX/WB blocks are `@(posedge clock1)` and ID/MEM blocks are `@(posedge clock2)`. The register file writes on `clock1`. The memory writes on `clock2`.

**Q26. Is this two-clock approach typical in real chips/FPGAs?**  
**A.** Not usually; real designs often use one clock and register everything cleanly at stage boundaries. Two-phase clocking is mainly used here as a conceptual teaching tool.

**Q27. What is the key timing guarantee you rely on with two-phase clocks?**  
**A.** Values produced on a `clock1` edge (e.g., EX/MEM outputs) are stable before the following `clock2` edge (MEM stage), and similarly decode results from `clock2` are stable before the next `clock1` edge (EX stage). That half-cycle spacing reduces accidental races.

---

## 6) Branches and “wrong-path” suppression

**Q28. How do BEQZ and BNEQZ work here?**  
**A.** The condition flag `cond` is computed as `(A == 0)` in EX and carried as `EX_MEM_cond`. `BEQZ` is taken when `cond==1`, `BNEQZ` is taken when `cond==0`. The branch target comes from `EX_MEM_ALUOut` computed as `NPC + imm`.

**Q29. Where does the branch decision influence instruction fetch?**  
**A.** `ifetch_addr = branch_taken ? EX_MEM_ALUOut : PC`. If a branch is taken, the fetch address is redirected to the computed target.

**Q30. What is `taken_branch` and why do you need it?**  
**A.** `taken_branch` is a one-cycle “squash” signal that prevents side effects (register writes, stores, and halting) from the instruction that is already behind a taken branch in the pipeline. Instead of flushing pipeline registers, the design gates write enables.

**Q31. How exactly are side effects suppressed on a taken branch?**  
**A.** The design gates:
- memory write enable: `mem_we` requires `!taken_branch`  
- register file write enable: `rf_we` requires `!taken_branch`  
- halting: `halted` only set on `HLT` when `!taken_branch`  
This ensures a wrong-path store/write/halt cannot commit.

**Q32. What is the branch penalty in this design?**  
**A.** At minimum you lose one useful issue slot because the instruction immediately behind the branch is squashed (its side effects are suppressed). The exact cycle-by-cycle view can be shown in a waveform: the fetched instruction stream redirects after the branch decision.

**Q33. Why do you use `===` for opcode checks in `branch_taken`?**  
**A.** `===` (case equality) treats X/Z explicitly. In simulation, it prevents unknown opcode bits from accidentally matching and producing confusing “maybe-branch” behavior.

---

## 7) Data hazards and bubble strategy

**Q34. Do you have forwarding or a hazard detection unit?**  
**A.** No. This CPU does not implement automatic stalling or forwarding. That’s an intentional scope choice.

**Q35. Then how do dependent instructions work correctly?**  
**A.** The test programs insert bubbles using a NOP-like instruction: `OR Rx, Rx, Rx`. This consumes pipeline time so the producer can reach writeback before the consumer reads the operand.

**Q36. Why is `OR R7, R7, R7` a safe NOP?**  
**A.** It computes `R7 OR R7`, which is exactly `R7`, and writes it back to `R7`. Architecturally, the register file state does not change, but the instruction still flows through the pipeline to create spacing.

**Q37. How would you remove the need for manual NOPs?**  
**A.** Add either (a) a hazard detection unit that stalls the pipeline when a RAW hazard is detected, and/or (b) forwarding paths from EX/MEM and MEM/WB back into the EX stage operand muxes.

---

## 8) Register file behavior

**Q38. How many registers are there and what width?**  
**A.** 32 registers (`regs[0..31]`), each 32-bit.

**Q39. How do you implement R0 as constant zero?**  
**A.** Reads from register 0 return `0`, and writes to register 0 are blocked (`if (we && wa != 0) regs[wa] <= wd`). This matches the MIPS convention.

**Q40. Are register reads synchronous or combinational?**  
**A.** Combinational reads (`assign rd1 = ... regs[ra1]`). Writes are synchronous on the regfile clock (`clock1`).

---

## 9) Memory model and load/store semantics

**Q41. Is instruction memory separate from data memory?**  
**A.** No. `memory_interface.v` models one unified memory array and exposes one instruction read address and one data read/write address.

**Q42. Are memory reads synchronous or asynchronous in this model?**  
**A.** Asynchronous (combinational) reads: `instr_out = mem[instr_addr]` and `data_out = mem[data_addr]`. Stores write on the memory clock edge.

**Q43. What does a load do in the pipeline?**  
**A.** In EX, the ALU computes the effective address. In MEM, `data_out` is captured into `MEM_WB_LMD`. In WB, that value is written into the destination register.

**Q44. What does a store do in the pipeline?**  
**A.** In EX, the ALU computes the effective address. In MEM, `mem[data_addr] <= data_in` occurs on the `clock2` edge when `mem_we` is asserted (and not squashed).

**Q45. What addressing mode do you support?**  
**A.** Base + signed 16-bit offset (word addressing). That’s enough to express stack-like and array-like patterns in small programs.

**Q46. What is a structural hazard concern in “unified memory” designs?**  
**A.** In real hardware, a single-ported memory cannot usually serve an instruction fetch and a data access in the same cycle. This model effectively gives you the reads you need for learning; a real implementation would use separate I/D memories (Harvard), a dual-ported RAM, or arbitration.

---

## 10) Halt behavior and program completion

**Q47. How does `HLT` work?**  
**A.** It is decoded as type `HALT`. When that instruction reaches WB (and is not squashed by a taken branch), the `halted` flag is set. All pipeline stage updates are guarded by `if (!halted)`, so execution stops cleanly.

**Q48. Does `HLT` stop immediately when fetched?**  
**A.** No. Like other instructions, it flows through the pipeline; the architectural halt commits in WB. That’s consistent with the idea that effects occur when an instruction “graduates” at the end of the pipeline.

---

## 11) Verification: what you tested and why it is convincing

**Q49. What are the key test programs and what do they prove?**  
**A.**
- **Add-three-numbers:** immediates + dependent adds -> validates ALU ops, writeback, and bubble timing.  
- **Memory-word demo:** `LW` -> `ADDI` -> `SW` -> validates address calc, load path, store path, and WB selection.  
- **Factorial loop:** loop with `LW`, `MUL`, `SUBI`, `BNEQZ`, `SW` -> validates branches, negative offsets, multi-iteration execution, and the interaction of memory + control flow.

**Q50. How do you observe internal correctness beyond final outputs?**  
**A.** The testbenches dump `.vcd` waveforms and also expose internal signals (PC, pipeline registers, ALU inputs/outputs, control flags). You can literally watch an instruction move across IF/ID/EX/MEM/WB and see when registers/memory update.

**Q51. Why is the `calculation/` folder important in a defense?**  
**A.** It proves you understand encoding and that the machine words in the testbenches were derived intentionally. It also documents hazard padding and branch offset arithmetic—exactly the details examiners like to probe.

**Q52. What would you do if a test failed—how would you debug?**  
**A.** First check the waveform at stage boundaries: verify IF fetched expected word, ID decoded the right type, EX computed ALUOut/cond correctly, MEM read/wrote correct address, and WB wrote the intended register. Because each stage is explicit, you can isolate the fault to one stage quickly.

---

## 12) Deep “design reasoning” questions (the ones that impress)

**Q53. What’s the difference between “instruction completes” and “instruction commits” in a pipeline?**  
**A.** Completion is when computation is done (e.g., ALU result computed), but commit is when architectural state changes (register write, memory write, halt). This design makes commit points explicit via `rf_we` and `mem_we`, which is why squashing wrong-path effects is feasible.

**Q54. How would you compute CPI for a program on this processor?**  
**A.** Ideal CPI tends toward 1 after fill, but penalties come from inserted NOP bubbles (software-visible stalls) and taken branches (squash). You count total clock1 cycles (or instruction fetches) and divide by committed instructions, excluding bubbles if you treat them as non-work.

**Q55. Where are the critical paths conceptually?**  
**A.** In a single-cycle CPU, the critical path would include instruction memory -> decode -> regfile -> ALU -> memory -> regfile. In this pipeline, those are broken across stages, but the combinational read memory/regfile/ALU portions still define timing inside each half-cycle.

**Q56. What would change if you moved to byte addressing (PC += 4)?**  
**A.** You’d make PC increment by 4, shift branch offsets (`imm << 2`), and adjust `LW/SW` addressing and memory indexing so that `mem[addr>>2]` is used (with alignment checks). This would make the model closer to standard MIPS.

**Q57. What’s the single biggest improvement you’d make next?**  
**A.** Add forwarding + hazard detection so that programs don’t need manual bubbles. It increases realism and demonstrates control complexity beyond basic decoding.

**Q58. Is your `memory_interface` synthesizable as-is?**  
**A.** The array itself can infer RAM in some flows, but fully asynchronous reads plus initialization loops are often simulation-oriented. For synthesis you’d typically use synchronous block RAM interfaces or vendor RAM primitives, and you’d revisit how instruction/data ports are implemented.

---

## 13) Practical run commands (if asked “how do we run it?”)

If you have Icarus Verilog installed:

- Add-three-numbers:  
  `iverilog -g2012 -s tb_add_three_numbers -o sim_add modellingOftheProcessor/*.v`  
  `vvp sim_add`

- Memory-word demo:  
  `iverilog -g2012 -s tb_memory_word -o sim_mem modellingOftheProcessor/*.v`  
  `vvp sim_mem`

- Factorial:  
  `iverilog -g2012 -s tb_factorial -o sim_fact modellingOftheProcessor/*.v`  
  `vvp sim_fact`

Waveforms: open the generated `.vcd` files in GTKWave (or any VCD viewer).
