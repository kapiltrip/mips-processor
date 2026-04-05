# Calculation Reference

This folder is meant to be a slow, readable companion to the Verilog code.  Every machine word we load into the testbenches comes
from a tiny bit of arithmetic, and the notes here unpack those calculations step by step so you can reproduce them by hand while
studying.

## How we turn mnemonics into 32-bit words

1. **Start with the assembly line.** Example: `ADDI R1, R0, 10`.
2. **Look up the opcode** in `mips.v` (bits `[31:26]`). `ADDI` is defined as `6'b001010`, so the leftmost six bits of the word
   become `001010`.
3. **Assign register numbers** to `rs`, `rt`, and `rd` using the register index (R0→`00000`, R1→`00001`, etc.). Place them in the
   order the instruction format expects: `opcode[31:26] | rs[25:21] | rt[20:16] | rd[15:11] | shamt/funct or imm[15:0]`.
4. **Prepare the immediate or funct field.**
   * For immediates, write the 16-bit value directly in binary. Positive numbers simply need enough leading zeros to fill 16 bits.
   * For negative numbers, compute the 16-bit two's-complement: invert the positive magnitude, add one, and keep all 16 bits.
   * For R-type instructions (like `ADD`), the final 11 bits are zeros in this design.
5. **Concatenate** the binary fields to form a 32-bit string. It helps to add spaces every four bits so you can sanity-check nibble
   boundaries.
6. **Convert binary to hex one nibble at a time.** Use the mapping `0000→0, 0001→1, …, 1001→9, 1010→A, 1011→B, 1100→C, 1101→D,
   1110→E, 1111→F`. The eight hex digits you collect become the machine word that gets loaded into memory.

## Sign-extension and negative offsets

* 16-bit immediates are sign-extended inside the pipeline, but the encoding step still writes all 16 bits explicitly. Copy bit 15
  into the upper 16 bits when you need the 32-bit version of an immediate during execution.
* To encode a negative offset (e.g., `-2`), first write the positive magnitude (`0000...0010` for `2`), invert the bits
  (`1111...1101`), then add one (`1111...1110`). That 16-bit pattern slides directly into the low half of the instruction word.
* Branch displacements work the same way: compute the signed distance from the *next* program counter (NPC) to the target label and
  encode that signed number in 16-bit two's-complement form.

## Hazard padding philosophy

The pipelined CPU does not implement automatic forwarding or stalling. When two adjacent instructions have a read-after-write
dependency, the testbenches insert self-OR NOPs (`OR Rx, Rx, Rx`) to consume a cycle and let the producer write back before the
consumer reads. Each per-program note below explains where those bubbles are inserted and which dependencies they protect.

## What to expect in each per-program note

Every markdown file in this folder follows a consistent structure so you can jump between them while learning:

* **Narrative walkthrough** that explains what the program is trying to achieve and how the binary fields are chosen.
* **Binary + hex tables** for quick lookup once you already understand the flow.
* **Inline examples** showing one instruction built from scratch, including nibble grouping and hex conversion.
* **Testbench reminders** about initialization, hazard padding, and the observable outputs when the program halts.
