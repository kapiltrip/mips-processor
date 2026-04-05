# Add-three-numbers testbench encoding notes

This walkthrough mirrors the first demo program. The goal is simple—load three small constants (10, 20, 25), add them over two
`ADD` operations, and halt—but the write-up lingers on the arithmetic so you can see how each hex word is born.

## Building each instruction in words, not just tables

1. **ADDI R1, R0, 10**
   * Opcode from `mips.v`: `ADDI = 001010`.
   * Registers: `rs = R0 = 00000`, `rt = R1 = 00001`.
   * Immediate: decimal 10 → binary `0000_0000_0000_1010`.
   * Concatenate: `001010 | 00000 | 00001 | 0000_0000_0000_1010` → `0010 1000 0000 0001 0000 0000 0000 1010`.
   * Nibbles to hex: `0010→2`, `1000→8`, `0000→0`, `0001→1`, `0000→0`, `0000→0`, `0000→0`, `1010→A`, giving `0x2801000A`.
2. **ADDI R2, R0, 20** follows the exact pattern with `rt = 00010` and immediate `0000_0000_0001_0100`, leading to
   `0x28020014`.
3. **ADDI R3, R0, 25** swaps in `rt = 00011` and immediate `0000_0000_0001_1001`, becoming `0x28030019`.
4. **OR R7, R7, R7** serves as a NOP. Its opcode is `000101`; `rs = rt = rd = R7 = 00111`; the remaining 11 bits are zeros.
   The grouped bits `0001 0100 1110 0111 0011 1000 0000 0000` map to `0x14E73800`. We reuse this exact word wherever a bubble is
   needed.
5. **ADD R4, R1, R2** is an R-type: opcode `000000`, `rs = R1 = 00001`, `rt = R2 = 00010`, `rd = R4 = 00100`, and 11 trailing
   zeros. That binary becomes `0x00222000`.
6. Another **OR R7, R7, R7** bubble at slot 6 prevents R3 from being read before R4 is written.
7. **ADD R5, R4, R3** mirrors step 5 but with `rs = R4 = 00100`, `rt = R3 = 00011`, `rd = R5 = 00101`, yielding `0x00832800`.
8. **HLT** ends the program. Its opcode `111111` sits in bits `[31:26]` with all lower bits zero → `1111 1111 0000 0000 0000 0000
   0000 0000` → `0xFC000000`.

## Quick reference table

| # | Assembly | Fields (opcode / rs / rt / rd / imm/funct) | 32-bit binary assembly | Hex word |
|---|----------|-------------------------------------------|-------------------------|----------|
|0|`ADDI R1, R0, 10`|`001010` / `00000` / `00001` / — / `0000_0000_0000_1010`|`0010 1000 0000 0001 0000 0000 0000 1010`|`0x2801000a`|
|1|`ADDI R2, R0, 20`|`001010` / `00000` / `00010` / — / `0000_0000_0001_0100`|`0010 1000 0000 0010 0000 0000 0001 0100`|`0x28020014`|
|2|`ADDI R3, R0, 25`|`001010` / `00000` / `00011` / — / `0000_0000_0001_1001`|`0010 1000 0000 0011 0000 0000 0001 1001`|`0x28030019`|
|3|`OR R7, R7, R7` (dummy)|`000101` / `00111` / `00111` / `00111` / `00000000000`|`0001 0100 1110 0111 0011 1000 0000 0000`|`0x14e73800`|
|4|`OR R7, R7, R7` (dummy)|same as above|`0001 0100 1110 0111 0011 1000 0000 0000`|`0x14e73800`|
|5|`ADD R4, R1, R2`|`000000` / `00001` / `00010` / `00100` / `00000000000`|`0000 0000 0010 0010 0001 0000 0000 0000`|`0x00222000`|
|6|`OR R7, R7, R7` (dummy)|same as #3|`0001 0100 1110 0111 0011 1000 0000 0000`|`0x14e73800`|
|7|`ADD R5, R4, R3`|`000000` / `00100` / `00011` / `00101` / `00000000000`|`0000 0000 1000 0011 0101 0000 0000 0000`|`0x00832800`|
|8|`HLT`|`111111` / — / — / — / `0000000000000000`|`1111 1111 0000 0000 0000 0000 0000 0000`|`0xfc000000`|

## Why the dummy ORs matter here

* The first `ADD` needs the results of two back-to-back `ADDI` instructions. A bubble after the immediate loads lets both writes
  finish before `ADD R4, R1, R2` reads `R1` and `R2`.
* The final `ADD` depends on `R4` from the previous `ADD`, so another bubble ensures the pipeline has time to write back before the
  read.

## How the testbench uses these words

* Registers start with their index as a readable baseline (R0=0, R1=1, …). `PC`, `halted`, and `taken_branch` are cleared.
* The table entries are written into `uut.Mem[0..8]` in order.
* Two-phase clocks tick for 50 iterations, plenty for this short program.
* After execution, the bench prints `R0`–`R5`. When everything is correct, `R5` shows `55` (10 + 20 + 25), proving the encodings
  and bubbles align with the pipeline timing.
