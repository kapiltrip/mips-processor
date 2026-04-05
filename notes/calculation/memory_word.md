# Memory load/add/store testbench encoding notes

This program demonstrates memory addressing: load a word from address 120, add 45, store it at 121, and halt. The text below walks
through the bit math in sentences before presenting the summary table.

## Building the words step by step

1. **ADDI R1, R0, 120**
   * Opcode `ADDI = 001010`.
   * Registers: `rs = R0 = 00000`, `rt = R1 = 00001`.
   * Immediate: 120₁₀ → `0000_0000_0111_1000`.
   * Concatenate → `001010 00000 00001 0000_0000_0111_1000` → grouped as `0010 1000 0000 0001 0000 0000 0111 1000` → hex
     `0x28010078`.
2. **OR R3, R3, R3** bubble
   * Opcode `000101`; `rs = rt = rd = R3 = 00011`; trailing zeros.
   * Binary `0001 0100 0110 0011 0001 1000 0000 0000` → hex `0x14631800`.
3. **LW R2, 0(R1)**
   * Opcode `LW = 001101`; `rs = R1 = 00001`; `rt = R2 = 00010`; immediate zero.
   * Binary `0011 0100 0000 0010 0000 0000 0000 0000` → hex `0x34220000`.
4. Another **OR R3, R3, R3** bubble (`0x14631800`) lets the load reach write-back before the next add uses R2.
5. **ADDI R2, R2, 45**
   * Opcode `001010`; `rs = R2 = 00010`; `rt = R2 = 00010`; immediate 45 → `0000_0000_0010_1101`.
   * Binary `0010 1000 0100 0010 0000 0000 0010 1101` → hex `0x2842002d`.
6. **OR R3, R3, R3** bubble (`0x14631800`) separates the add from the store.
7. **SW R2, 1(R1)**
   * Opcode `SW = 001110`; `rs = R1 = 00001`; `rt = R2 = 00010`; immediate 1 → `0000_0000_0000_0001`.
   * Binary `0011 1000 0010 0010 0000 0000 0000 0001` → hex `0x38220001`.
8. **HLT** closes execution: `1111 1111 0000 0000 0000 0000 0000 0000` → `0xFC000000`.

## Quick reference table

| # | Assembly | Fields (opcode / rs / rt / rd / imm) | 32-bit binary assembly | Hex word |
|---|----------|--------------------------------------|-------------------------|----------|
|0|`ADDI R1, R0, 120`|`001010` / `00000` / `00001` / — / `0000_0000_0111_1000`|`0010 1000 0000 0001 0000 0000 0111 1000`|`0x28010078`|
|1|`OR R3, R3, R3` (dummy)|`000101` / `00011` / `00011` / `00011` / `00000000000`|`0001 0100 0110 0011 0001 1000 0000 0000`|`0x14631800`|
|2|`LW R2, 0(R1)`|`001101` / `00001` / `00010` / — / `0000_0000_0000_0000`|`0011 0100 0000 0010 0000 0000 0000 0000`|`0x34220000`|
|3|`OR R3, R3, R3` (dummy)|same as #1|`0001 0100 0110 0011 0001 1000 0000 0000`|`0x14631800`|
|4|`ADDI R2, R2, 45`|`001010` / `00010` / `00010` / — / `0000_0000_0010_1101`|`0010 1000 0100 0010 0000 0000 0010 1101`|`0x2842002d`|
|5|`OR R3, R3, R3` (dummy)|same as #1|`0001 0100 0110 0011 0001 1000 0000 0000`|`0x14631800`|
|6|`SW R2, 1(R1)`|`001110` / `00001` / `00010` / — / `0000_0000_0000_0001`|`0011 1000 0010 0010 0000 0000 0000 0001`|`0x38220001`|
|7|`HLT`|`111111` / — / — / — / `0000_0000_0000_0000`|`1111 1111 0000 0000 0000 0000 0000 0000`|`0xfc000000`|

## Hazard padding explained

* The OR at index 1 keeps the load from racing the address setup in index 0.
* The OR at index 3 allows `LW` to write R2 before `ADDI R2, R2, 45` reads it.
* The OR at index 5 lets the add complete before the store consumes the updated R2 value.

## Testbench reminders

* Registers are initialized to their indices for easy visibility; memory location 120 starts at decimal 85 (`uut.Mem[120] = 32'd85`).
* Program words above load into `uut.Mem[0..7]`; two-phase clocks run 60 iterations to cover the sequence safely.
* When finished, the bench prints `Mem[120]` (original 85) and `Mem[121]` (expected 130 after adding 45), confirming that the hex
  encodings and hazard bubbles lined up with the pipeline timing.
