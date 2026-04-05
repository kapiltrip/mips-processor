# Factorial testbench encoding notes

This is the longest example and shows a full loop. The CPU reads `n` from memory address 200, multiplies down to 1, stores the
factorial at address 198, and halts. The comments below spell out how the branch offset and negative store offset are encoded, and
how each word becomes hex.

## Building the words slowly

1. **ADDI R10, R0, 200**
   * Opcode `001010`; `rs = R0 = 00000`; `rt = R10 = 01010`.
   * Immediate 200₁₀ = `0000_0000_1100_1000`.
   * Binary grouping: `0010 1000 0000 1010 0000 0000 1100 1000` → hex `0x280a00c8`.
2. **ADDI R2, R0, 1** seeds the accumulator.
   * Same opcode; `rt = R2 = 00010`; immediate `0000_0000_0000_0001`.
   * Binary `0010 1000 0000 0010 0000 0000 0000 0001` → hex `0x28020001`.
3. **LW R3, 0(R10)** pulls `n` from memory.
   * Opcode `LW = 001101`; `rs = R10 = 01010`; `rt = R3 = 00011`; immediate zeros.
   * Binary `0011 0101 0100 0011 0000 0000 0000 0000` → hex `0x35430000`.
4. **OR R7, R7, R7** bubble (`0x14e73800`) lets the load complete before multiplication.
5. **MUL R2, R3, R2** performs `R2 = R3 * R2`.
   * Opcode `MUL = 000100`; `rs = R2 = 00010`; `rt = R3 = 00011`; `rd = R2 = 00010`; funct bits zero.
   * Binary `0001 0000 0100 0011 0010 0000 0000 0000` → hex `0x10431000`.
6. **OR R7, R7, R7** bubble separates the multiply from the decrement.
7. **SUBI R3, R3, 1** counts down.
   * Opcode `SUBI = 001011`; `rs = R3 = 00011`; `rt = R3 = 00011`; immediate `0000_0000_0000_0001`.
   * Binary `0010 1100 0110 0011 0000 0000 0000 0001` → hex `0x2c630001`.
8. **OR R7, R7, R7** bubble separates the subtract from the branch.
9. **BNEQZ R3, loop** branches back five words when `R3 != 0`.
   * NPC when executing this instruction is 9, and the loop target is instruction index 4, so offset = `4 - 9 = -5`.
   * `-5` in 16-bit two's-complement: start with `0000_0000_0000_0101`, invert → `1111_1111_1111_1010`, add one →
     `1111_1111_1111_1011`.
   * Opcode `BNEQZ = 001111`; `rs = R3 = 00011`; `rt` is unused (zeros). Binary `0011 1100 0110 0000 1111 1111 1111 1011` →
     hex `0x3c60fffb`.
10. **SW R2, -2(R10)** stores the factorial two words below the original pointer (200 - 2 = 198).
    * Offset `-2` in two's-complement: `0000_0000_0000_0010` → invert `1111_1111_1111_1101` → add one `1111_1111_1111_1110`.
    * Opcode `SW = 001110`; `rs = R10 = 01010`; `rt = R2 = 00010`.
    * Binary `0011 1001 0100 0010 1111 1111 1111 1110` → hex `0x3942fffe`.
11. **HLT** marks the end: `1111 1111 0000 0000 0000 0000 0000 0000` → `0xFC000000`.

## Quick reference table

| # | Assembly | Fields (opcode / rs / rt / rd / imm/funct) | 32-bit binary assembly | Hex word |
|---|----------|-------------------------------------------|-------------------------|----------|
|0|`ADDI R10, R0, 200`|`001010` / `00000` / `01010` / — / `0000_0000_1100_1000`|`0010 1000 0000 1010 0000 0000 1100 1000`|`0x280a00c8`|
|1|`ADDI R2, R0, 1`|`001010` / `00000` / `00010` / — / `0000_0000_0000_0001`|`0010 1000 0000 0010 0000 0000 0000 0001`|`0x28020001`|
|2|`LW R3, 0(R10)`|`001101` / `01010` / `00011` / — / `0000_0000_0000_0000`|`0011 0101 0100 0011 0000 0000 0000 0000`|`0x35430000`|
|3|`OR R7, R7, R7` (dummy)|`000101` / `00111` / `00111` / `00111` / `00000000000`|`0001 0100 1110 0111 0011 1000 0000 0000`|`0x14e73800`|
|4|`MUL R2, R3, R2`|`000100` / `00010` / `00011` / `00010` / `00000000000`|`0001 0000 0100 0011 0010 0000 0000 0000`|`0x10431000`|
|5|`OR R7, R7, R7` (dummy)|same as #3|`0001 0100 1110 0111 0011 1000 0000 0000`|`0x14e73800`|
|6|`SUBI R3, R3, 1`|`001011` / `00011` / `00011` / — / `0000_0000_0000_0001`|`0010 1100 0110 0011 0000 0000 0000 0001`|`0x2c630001`|
|7|`OR R7, R7, R7` (dummy)|same as #3|`0001 0100 1110 0111 0011 1000 0000 0000`|`0x14e73800`|
|8|`BNEQZ R3, loop` (offset = -5)|`001111` / `00011` / — / — / `1111_1111_1111_1011`|`0011 1100 0110 0000 1111 1111 1111 1011`|`0x3c60fffb`|
|9|`SW R2, -2(R10)`|`001110` / `01010` / `00010` / — / `1111_1111_1111_1110`|`0011 1001 0100 0010 1111 1111 1111 1110`|`0x3942fffe`|
|10|`HLT`|`111111` / — / — / — / `0000000000000000`|`1111 1111 0000 0000 0000 0000 0000 0000`|`0xfc000000`|

## Why the bubbles sit where they do

* **After the load (index 3):** ensures `R3` holds the fetched operand before the multiply reads it.
* **After the multiply (index 5):** lets the product reach write-back before `SUBI` touches `R3` and the loop body moves on.
* **After the subtract (index 7):** allows `R3` to be updated before the branch tests it.

## Loop and offset intuition

Think of the branch offset as “how many instructions to jump relative to the *next* instruction.” When the `BNEQZ` at index 8 runs,
`NPC` has already advanced to 9, so jumping back to instruction 4 is a delta of `-5`. Encoding `-5` with two's-complement makes the
branch field match what the hardware expects. The store uses the same arithmetic: writing to `R10 - 2` converts to the two's-
complement pattern `1111_1111_1111_1110`, naturally placing the result at address 198 when `R10` holds 200.

## Testbench reminders

* Memory location 200 is preloaded with `n` (e.g., 7); location 198 will catch the factorial.
* Program words occupy `uut.Mem[0..10]`; two-phase clocks run for 200 iterations to let the loop converge.
* Register file is seeded with index values for readability; `PC`, `halted`, and `taken_branch` start at zero.
* The bench prints `Mem[200]` and `Mem[198]` at the end; with `n = 7`, the output should show `5040` in `Mem[198]`, confirming the
  encodings, offsets, and bubble placement are correct.
