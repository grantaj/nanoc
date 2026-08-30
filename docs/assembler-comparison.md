# How native C64 assemblers actually assemble

nanoc was designed independently from the classic C64 assemblers. It was not derived from Commodore's Macro Assembler Development System, Supermon64, Turbo Assembler, or Turbo Macro Pro.

That makes the comparison more interesting, not less. All four approaches are plausible answers to the same machine: a 1 MHz 6502/6510 with 64 KB of address space, slow storage, and strong pressure to make every resident byte earn its place.

The important comparison is therefore not which user interface each tool has. It is:

> **What representation survives while assembly is happening, and how are unknown addresses turned into final machine bytes?**

That question produces four quite different designs.

## At a glance

| System | Source while assembling | Assembly strategy | Forward references | Output |
| --- | --- | --- | --- | --- |
| Supermon64 | No source program representation; one typed instruction at a time | Parse one instruction and write it immediately | No symbolic forward-reference mechanism | Directly into the requested C64 memory address |
| Commodore Macro Assembler Development System | Source file is read again | Conventional two-pass assembly | Pass 1 builds symbols and assumes the long form when operand size is unknown; pass 2 rereads source | MOS-format interface/object file, later consumed by a loader |
| Turbo Assembler / Turbo Macro Pro | Complete source remains resident in Turbo's compact binary source format | Two-pass assembly over resident source | Pass 1 estimates layout; pass 2 resolves labels; changed zp/absolute widths can cause a phase error | Main memory, an assembly/object bank, disk, or another C64 depending on version |
| nanoc | Only the current source line is resident | One source pass into a final-size staged machine-code image | Waiting references are stored in the output bytes themselves where possible, otherwise in small fixups | Final-size staged bytes are validated, then copied to target memory |

The phrase **final-size staged machine-code image** matters. nanoc does not normally write the user's target memory while parsing, because an error should not leave a half-written program. But its staging area is already the machine-code image: there is no intermediate instruction representation that later has to be lowered into bytes.

## Supermon64: the target memory is the program representation

Supermon64 is primarily a machine-language monitor. Its assembler command is intentionally small:

```text
A 2000 LDA #$12
```

Supermon converts that instruction to `A9 12`, stores the bytes beginning at `$2000`, and prompts at `$2002` for the next instruction. Existing code can be changed by moving the cursor back and reassembling an instruction in place.

Conceptually:

```text
typed instruction
       |
       v
parse mnemonic + operand
       |
       v
machine bytes
       |
       v
C64 memory at the requested address
```

There is essentially no assembly-wide representation to preserve. The current address is already known, and operands are numeric addresses rather than symbolic labels. That eliminates the whole forward-reference problem.

### What Supermon supports

The assembler is only one part of a monitor that also provides disassembly, memory display/editing, register inspection, searching, filling, moving and comparing memory, and execution controls. Its numeric parser accepts hexadecimal and, in later Supermon+64, decimal, octal and binary forms.

What it deliberately does **not** provide is the source-program machinery associated with a symbolic assembler:

- no source file held for later reassembly;
- no label table;
- no forward symbolic references;
- no macros;
- no include processing;
- no assembly-wide data or expression language.

The benefit is immediacy. The bytes you are editing are the bytes that execute.

This is the smallest possible answer to the assembly problem, but only because it solves a smaller problem than nanoc.

## Commodore MADS: reread source, but be conservative about unknown widths

Commodore's 1982 **Macro Assembler Development System** is a much closer comparison to nanoc because it is a real symbolic assembler intended for substantial programs.

It is also a visibly older development-system design. `EDITOR64` creates source files. `ASSEMBLER64` is a separate program that later reads those files. Listings, errors, object/interface output, loaders, monitors and cross-reference generation are separate tools.

The assembler itself is explicitly two-pass.

### Pass 1

It reads source sequentially and builds the symbol table. A symbol used before definition is entered as undefined and may be filled in when its definition is later encountered.

For an instruction operand containing an unresolved expression, the assembler cannot yet know whether the value will fit in zero page. The manual says that pass 1 therefore reserves **two operand bytes**, the largest case.

Conceptually:

```text
source file
    |
    v
pass 1
    |
    +--> build/complete symbol table
    `--> calculate addresses using conservative operand sizes
```

### Pass 2

The source is read again. This time forward symbols have values and normal opcode/operand bytes can be generated.

```text
source file -- read again --> pass 2 --> object/interface output
                    ^
                    |
                symbol table
```

The surviving representation between the two passes is therefore principally **the source plus the symbol table**. The assembler does not need to remember a compact semantic record for each instruction because it can simply parse the original statement again.

### The zero-page decision is surprisingly close to nanoc

The MADS manual makes an unusually explicit tradeoff. If an unresolved forward operand eventually turns out to fit in one byte, pass 1 has already allowed two bytes for it. Rather than move later code, the assembler leaves the instruction in the longer form. The manual describes the result as one wasted byte.

That is substantially the same policy nanoc independently arrived at:

```text
known $00xx value       -> use legal zero-page form
unknown ordinary label  -> use legal absolute form
```

The important difference is **what happens to the source**.

MADS says:

```text
read source -> learn symbols -> read source again -> emit bytes
```

nanoc says:

```text
read source once -> emit final-size bytes now -> patch unknown values later
```

So the width policy is historically very plausible even though nanoc's representation strategy was developed independently.

### Forward-reference limits

MADS supports what its manual calls one level of forward reference. A normal instruction may refer to a label defined later, but computed chains of forward definitions are restricted. Expressions on the right side of an equate must use already-defined symbols.

That restriction keeps pass-two resolution straightforward. It is another example of a period assembler preferring a simple semantic rule over a general dependency solver.

### What MADS supports

Compared with nanoc today, MADS has a broader source language and development surface. The C64 macro version includes facilities such as:

- labels and constants;
- `.BYTE`, `.WORD` and `.DBYTE` data;
- source inclusion/library handling with `.LIB` / `.FILE`;
- macro definitions and calls with parameters;
- conditional assembly inherited from the resident assembler family;
- listing, error and interface/object output controls;
- symbol-table and cross-reference output through the wider tool suite.

Its output path is also different. The assembler writes an interface/object file in the MOS Technology textual record format rather than simply creating a normal C64 PRG in place; a separate loader performs the loading step.

That separation reflects the development-system ancestry of the program: it was descended from MOS/Commodore tooling rather than designed solely as an interactive C64 editor/assembler.

## Turbo Assembler / Turbo Macro Pro: keep a compact editable source and run two passes over it

Turbo Assembler solves a different problem again: make the complete edit-assemble-run loop fast and pleasant while remaining native on the C64.

Its editor and assembler are highly integrated. The complete source is resident and editable, and saved Turbo source files use a **binary source format** rather than an ordinary ASCII/PETSCII text file. Tools such as TMPview exist specifically to decode that binary source into textual source for cross assemblers.

It is tempting to call this binary source an IR. That is slightly misleading. It is better understood as Turbo's compact **editor/source representation**: the source itself remains the thing that is traversed by the assembler. It is not a separate lowered instruction graph or object-code representation produced by a parsing phase.

### Two-pass assembly

Turbo Macro Pro is a two-pass assembler. The first pass walks the resident source, expands the relevant source constructs, builds the label table and computes addresses. The second pass walks the source again using resolved label values and emits the assembled program.

Conceptually:

```text
resident binary-format source
          |
          +-----------------------+
          |                       |
          v                       v
       pass 1                  pass 2
          |                       |
   labels + layout  ----------> final bytes
```

Because the source remains resident, reparsing is cheap compared with repeatedly reading disk files. That helps make the two-pass design practical in an interactive development environment.

### Forward references and phase errors

For an unresolved direct address such as:

```asm
lda table,x
```

pass 1 does not yet know whether `table` will be in zero page, so it assumes a two-byte address. If pass 2 discovers that the symbol is actually zero page and therefore changes the instruction width, all later pass-1 addresses would shift. Turbo reports a **phase error** and the source must be assembled again with the improved information.

This is an important contrast with both MADS and nanoc:

```text
MADS   unknown -> long form -> keep long form even if zero page
TMP    unknown -> long assumption -> detect changed layout / phase error
nanoc  unknown -> long form -> keep long form; no layout reconsideration
```

TMP is trying harder to preserve the short form where possible. nanoc deliberately gives up that occasional byte to remove the phase/layout problem entirely.

### What Turbo/TMP supports

Turbo Assembler Macro and Turbo Macro Pro are substantially richer source languages than nanoc's current self-hosting assembler. Depending on version they include facilities such as:

- labels and constants;
- macros with arguments and recursive macro use;
- local/block scoping;
- source includes;
- conditional assembly;
- a much richer expression language with arithmetic and bitwise operations;
- multiple program-counter changes with `* = ...`;
- data and string pseudo-operations;
- mutable assembly-time variables and looping/goto-style assembly controls;
- illegal-opcode support in later variants.

The integrated environment also offers several output arrangements. An unexpanded C64 can assemble directly into main memory. REU and other variants distinguish source, assembly and object banks. Other commands can assemble to disk or, in dual-C64 versions, send the output to another machine.

That breadth explains some of its machinery. TMP is not merely translating a small assembly language: it is also a native editor, macro processor and rapid development environment.

## nanoc: make machine code the persistent representation

nanoc starts from a constraint that none of those systems make central: the real assembler source tree is much larger as text than the generated assembler is as machine code, yet the assembler should be able to assemble itself on a stock C64.

Keeping the whole source resident is therefore unattractive. Reading the whole source twice is possible in principle, but also unnecessary if most statements can be completely understood the first time they are seen.

The production path instead keeps one 256-byte line buffer:

```text
disk -> one source line -> parse
                         |
                         v
                 final-size staged bytes
```

Once a statement has become bytes, its source text has no further job and the buffer can be reused.

### Known instructions already are their final representation

For:

```asm
lda #$20
```

the persistent result is simply:

```text
A9 20
```

There is no token object, instruction record, AST node or later emission pass.

The same is true for known data and strings.

### Forward references borrow the output bytes

For the common unresolved plain 16-bit label, the two operand bytes have already been reserved at their final position. Until the label value is known they temporarily store a pointer to the previous waiting reference.

Thus:

```text
20 ?? ??
   ^^^^^
   final JSR operand bytes
   temporarily: linked-list pointer
```

The symbol entry stores the head of the chain. When the label is defined, nanoc walks the chain and overwrites the temporary links with the real little-endian target address.

The data structure disappears by becoming the output.

One-byte references, relative branches and expressions cannot use the two-byte trick, so they receive small explicit exceptional fixups instead.

### Why staging is not an IR

nanoc writes these bytes into a staging region rather than immediately into the caller's target address. That provides failure atomicity: undefined symbols, branch-range failures and workspace exhaustion are detected before the target image is committed.

But the staging region is not an intermediate instruction language. Its bytes already have final offsets and final widths, and after outstanding values are patched the final step is a literal copy.

```text
source line
    |
    v
machine-code bytes + minimal unresolved residue
    |
    v
same machine-code bytes, now fully patched
    |
    v
copy to target
```

This is the central technical difference from a conventional two-pass design.

## Feature comparison

The feature table is deliberately coarse: the historical assemblers exist in many versions, especially Turbo Assembler. It is meant to show which capabilities shape their architecture, not to serve as a compatibility reference.

| Capability | Supermon64 | Commodore MADS | Turbo/TMP | nanoc |
| --- | :---: | :---: | :---: | :---: |
| Symbolic labels | — | yes | yes | yes |
| Forward labels | — | yes, bounded semantics | yes | yes |
| Local/block labels | — | limited/no modern block model | yes | simple current-global scope |
| Macros | — | yes | yes | — |
| Conditional assembly | — | yes | yes | — |
| Includes | — | yes | yes | yes, bounded depth |
| Expressions | numeric operand only | arithmetic expressions, forward restrictions | rich arithmetic/bitwise expressions | one optional `+`/`-`, optional `<`/`>` |
| Data pseudo-ops | — | yes | yes | `byte`, `word`, `string` |
| Multiple origin changes | user chooses each typed address | supported via location counter | yes | one origin before address-bearing output |
| Full source resident while assembling | no | no; reread from source file | yes | no |
| Source parsed more than once | no | yes | yes | no |
| Separate per-instruction IR | no | no | no; compact binary source is still source | no |
| Output bytes used as unresolved-reference storage | no need | no | not the central model | yes |
| Layout can require another assembly | no | no; may leave long forward operands | yes, phase errors | no |
| Output initially written directly to executable memory | yes | no | often yes / assembly bank | no; validated staging first |

## The most revealing comparison

The four systems can be reduced to what they retain:

```text
Supermon
    retain almost nothing
    the target bytes are the program

Commodore MADS
    retain symbol knowledge
    keep/re-read the source file

Turbo / TMP
    retain symbol knowledge
    keep the complete compact editable source resident

nanoc
    discard each source line
    retain the final-size output bytes themselves
    plus only unresolved symbolic residue
```

This is why nanoc feels plausible as a period design even though it was developed in isolation.

Nothing in its core strategy requires a modern compiler concept. On the contrary, the crucial decisions are exactly the sort of decisions forced by a small 8-bit machine:

- a source line is temporary because disk can provide it again only if needed;
- machine code is dramatically smaller than source, so turn text into bytes as early as possible;
- if an output field is empty while waiting for a label, let those bytes do useful work;
- if choosing a conservative absolute instruction removes an entire layout problem, spend the byte;
- use fixed bounded storage instead of solving allocation problems the program does not have.

The closest historical echo is perhaps Commodore MADS's treatment of unknown zero-page/absolute operands: **when the width is unknown, choose the long form and accept the byte**. nanoc independently takes the same trade, then goes one step further by making the already-sized output image replace the need for a second source pass.

## Sources and limits of the comparison

The historical tools have many versions, particularly the Turbo Assembler family, so this document avoids claiming byte-level internals that are not documented. “Turbo binary source” refers to the documented binary format used to save native Turbo/TMP source files, not to a claim that Turbo constructs a modern compiler IR.

Primary or near-primary material used for this comparison:

- Commodore, *The Commodore 64 Macro Assembler Development System* manual: <https://github.com/dmarlowe69/cbm_mads/blob/master/CBM%20Documentation/assembler.txt>
- Michael Steil's history of the MOS/Commodore resident assembler family: <https://www.pagetable.com/?p=1522>
- Jim Butterfield, *Supermon64*, Compute!, January 1983: <https://www.atarimagazines.com/compute/issue32/082_1_SUPERMON_64.php>
- preserved and commented Supermon+64 sources and usage material: <https://github.com/jblang/supermon64>
- official Turbo Macro Pro documentation: <https://turbo.style64.org/docs/about-turbo-macro-pro-c64-assemblers>
- Turbo Macro Pro editor and memory-bank documentation: <https://turbo.style64.org/docs/turbo-macro-pro-editor> and <https://turbo.style64.org/docs/turbo-macro-pro-overview>
- Turbo/TMP syntax and pseudo-operation documentation: <https://turbo.style64.org/docs/turbo-macro-pro-tmpx-syntax>
- Turbo binary-source portability notes: <https://turbo.style64.org/docs/portability-considerations-re-syntax>

For the two-pass/phase-error behavior of native Turbo Macro Pro, the C64 OS programmer's guide provides a particularly clear operational description: <https://c64os.com/c64os/programmersguide/devenvironment>.

The point of these references is not to claim ancestry. nanoc's assembler architecture was developed from its own self-hosting and memory constraints. The comparison shows that the resulting choices belong comfortably within the design space of real native 6502 development tools.
