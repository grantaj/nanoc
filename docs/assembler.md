# Assembler design

nanoc's assembler is deliberately shaped by the 6502 and the C64 rather than by a textbook compiler pipeline. The implementation is easiest to understand as a sequence of machine-state changes:

```text
read one source line
        |
        v
parse transient source views
        |
        v
stage final-size machine bytes
        |
        +--> ordinary unresolved 16-bit labels
        |    chain through their own operand bytes
        |
        `--> exceptional byte / relative / expression cases
             use small fixed fixup records
        |
        v
label definition patches everything waiting for that label
        |
        v
EOF validates that nothing remains unresolved
        |
        v
copy the staged image to the target address
```

There is one source parse. There is no layout-convergence pass, no stored instruction stream, and no generic relocation stage.

## The design rules

Several choices recur throughout the assembler.

### Keep source text in place

`ass/parser.asm` returns pointer/length views into the current source line. A statement name or operand is not copied merely because scanning and parsing are conceptually different operations.

The production path in `ass/source.asm` reuses one 256-byte line buffer. That forces a useful question: **what actually needs to outlive this line?**

Usually the answer is “almost nothing”. Known instructions and data immediately become staged machine bytes. A name is copied only when textual identity must survive, principally for a symbol that may be referenced after the line buffer has been reused.

### Represent only what must survive

A known instruction such as:

```asm
lda #$20
```

has no persistent instruction object. Once parsed, it is already bytes.

Likewise a known `word $1234` becomes `$34 $12`; a string becomes its bytes plus NUL; a label that is already known becomes a fixed value.

Persistent structures exist only for information that still has future work to do.

### Decide final width when the statement is parsed

6502 direct addressing sometimes offers both a zero-page and an absolute encoding. A known numeric value chooses immediately: a one-byte value prefers the short legal mode; otherwise the long legal mode is used.

An unresolved ordinary label is an address. If both short and long modes exist, nanoc deliberately chooses the long mode and never later shortens it. `<label` or `>label` explicitly asks for a byte-sized value and therefore permits a short mode.

This trades an occasional byte of output for the removal of an entire layout-relaxation problem. For a small native teaching assembler, that is a very good trade.

Relative branches are already fixed-width; only their signed operand byte may remain unresolved.

### Use storage that already exists

The most common forward reference is a plain 16-bit label address. Its two final operand bytes already exist in the staged image but have no useful value until the label is defined.

Those bytes temporarily form a linked list of unresolved references.

That means ordinary forward word references need no separate relocation record at all.

### Prefer a small special case to a uniform abstraction

Not every unresolved value has two output bytes available. A forward branch has only one operand byte; `<label` is one byte; `word label+1` needs to remember an addend.

Those uncommon cases use a small fixed-size fixup record in `ass/representation.asm`.

The assembler therefore has two deliberately different mechanisms:

```text
common exact 16-bit label reference  -> operand-byte chain
exceptional byte/expression/relative -> eight-byte fixup record
```

A generic relocation representation would be more uniform but less simple.

### Prefer linear scans when they remove structures

The symbol table is linear. Mnemonic lookup is linear. `instruction.asm:findOpcode` scans the shared 256-entry opcode table in reverse rather than maintaining another mnemonic/mode-to-opcode index.

On a 1 MHz machine these choices are not “free”, but assembly speed is not the scarce resource here. RAM, code size, and the reader's ability to see the whole mechanism matter more.

## Source and parser

There are two assembler entry paths.

`assemble` consumes an already resident caller-owned `[ZP_PTR1, sourceEnd)` region. It exists primarily for small native tests.

`assembleFile` is the production path. `source.asm:readSourceLine` reads one logical line through the C64 KERNAL, writes a NUL terminator, and `prepareSourceLine` exposes that line through the same parser contract.

`parser.asm:nextStatement` returns only:

```text
STATEMENT_LABEL
STATEMENT_SYMBOL
STATEMENT_INSTRUCTION
STATEMENT_EOF
```

The “instruction” category means an instruction-like statement name. `assembler.asm:processStatement` decides whether that name is `include`, one of the data operations `byte` / `word` / `string`, or a real 6502 mnemonic.

There is deliberately no parser-level directive object or directive category.

A label consumes only its own lexeme. Thus a real source form such as:

```asm
label: word 0
```

can be returned as two successive statements from the same line before `assembleFile` asks for another line.

## Instruction knowledge is shared with the disassembler

The assembler and disassembler share the same core description of the 6502 instruction set:

```text
dis/mnemonic_table.asm   fixed three-byte mnemonic names
dis/opcode_table.asm     256 opcode -> mnemonic/mode entries
dis/mode_ids.inc         addressing-mode IDs
dis/mode_widths.asm      operand width for each mode
```

The opcode table has **256 entries**, one for every byte value `$00..$ff`. Each entry is two bytes: mnemonic index and addressing-mode index.

The original disassembler indexes this table directly from an opcode. The assembler takes the opposite question—“which opcode has this mnemonic and mode?”—and answers it by scanning the same table in `instruction.asm:findOpcode`.

That linear scan keeps one authoritative instruction-set table instead of adding a reverse index.

The disassembler's operand formatters live in `dis/modes.asm`. Their input operand pointer is the zero-page pointer `p`; they format the operand and return with X and Y preserved. Operand width is no longer returned by the formatter: both directions use the separate shared `modeOperandWidths` table.

## The tiny value language

`ass/value.asm` intentionally does not implement a general expression parser. Its complete grammar is:

```text
[< | >] atom [ + atom | - atom ]
```

where an atom is:

```text
$hex
decimal
'c'
constant
label
```

There is no precedence, tree, recursion, or parenthesized expression language.

A fixed expression collapses immediately to a 16-bit value. An unresolved expression preserves only:

```text
symbol entry
16-bit addend
optional < or > selector
```

The source substring itself is not retained.

This is enough for the source forms the assembler itself uses, including values such as `sourceEnd+1`, `#<name`, `#>name`, and table offsets.

## The symbol table

`ass/symbols.asm` uses one caller-owned region in two directions:

```text
symbolTableStart                         symbolTableLimit
      |                                         |
      v                                         v
+-----+-----+-----+---- ... ----+      +-------------------+
| entry | entry | entry          | ---> |       names       |
+-----+-----+-----+---- ... ----+      +-------------------+
      entries grow upward          names grow downward
```

Each fixed-size entry is seven bytes:

```text
name pointer     2
name length      1
payload          2
scope            1
kind             1
```

The two-byte payload deliberately has different meanings in mutually exclusive states:

```text
constant / defined label -> final 16-bit value
undefined label          -> head of word-reference chain
```

An undefined label has no final value yet. A defined label no longer has outstanding ordinary word references. Storing both fields would waste two bytes in every entry.

Names are owned because the line buffer will be reused; lookup remains a simple linear walk.

## The operand-byte forward-reference chain

This is the key representation trick in the assembler.

Suppose the final program starts at `$2000`, staging starts at `$6000`, and the source contains:

```asm
    jsr later
    jsr later
later:
    rts
```

After the first JSR is parsed, `$20` is staged at `$6000`. The two operand bytes are at `$6001/$6002`. `stagePlainWordReference` reserves them and `linkWordReference` writes the previous chain head into those bytes. There was no previous reference, so they contain `$0000`:

```text
staging address   bytes             temporary meaning
$6000             20               JSR opcode
$6001-$6002       00 00            end of reference chain

symbol `later` payload = $6001      chain head
```

The second JSR starts at `$6003`. Its operand bytes point to the first reference:

```text
$6000             20
$6001-$6002       00 00            next = none
$6003             20
$6004-$6005       01 60            next = $6001

symbol `later` payload = $6004      new chain head
```

No separate record was allocated for either reference.

When `later:` appears, the final target PC is `$2006`. `defineLabel` first captures the old chain head, then changes the symbol entry to the defined state with payload `$2006`. `resolveWordReferencesForSymbol` walks the staged links:

```text
$6004 -> reads next $6001 -> writes 06 20
$6001 -> reads next $0000 -> writes 06 20
```

The staged bytes are now ordinary final machine code:

```text
20 06 20   20 06 20   60
JSR $2006  JSR $2006   RTS
```

The temporary data structure has literally turned into the output bytes it was standing in for.

## Exceptional fixups

The two-byte trick cannot represent every unresolved field. `ass/representation.asm` therefore reserves eight bytes for each exceptional fixup:

```text
kind             1
staging address  2
symbol entry     2
addend           2
prefix           1
```

Current kinds cover:

- one-byte instruction operands;
- word expressions;
- relative branches;
- one-byte data values.

The staged machine image grows upward from `stagingStart`; fixup records grow downward from `stagingLimit`:

```text
stagingStart                              stagingLimit
     |                                         |
     v                                         v
+---- final-size bytes ---->       <---- fixups ----+

                 collision -> ASSEMBLE_WORK_FULL
```

Resolved records are simply marked `FIXUP_NONE`; their storage is not reclaimed. These cases are expected to be uncommon, and a free list would cost more conceptual machinery than it would save.

When a label is defined, `resolveSymbolFixups` scans the small fixup area and patches every matching record immediately. Relative fixups share the same `encodeRelativeByte` routine as already-known branches, so the `-128..127` rule has one implementation.

## Staging makes failure atomic

`representation.asm:stageByte` advances two things together:

- `stagingPtr`, where the temporary image is stored;
- `assemblyPtr`, the final target PC used to define addresses.

The target memory itself is not written while parsing.

At EOF, `finishAssembly` performs three checks/actions:

```text
sealRepresentation
allLabelsDefined
allFixupsResolved
```

Only if those succeed does `copyRepresentation` copy the staged bytes literally to `assemblyStart`.

An undefined symbol, out-of-range branch, bad one-byte value, or workspace collision therefore cannot leave half an assembled program in the target region.

Because widths were already final when each statement was parsed, this final copy has no compaction or relocation work to do.

## Origin and the program counter

`assemblyPtr` is the assembler's one location counter. Its input value is the default target origin.

A leading:

```asm
* = $2000
```

may replace that origin once, before any address-bearing construct. A label, instruction, or data declaration closes the origin window. A later origin is `ASSEMBLE_BAD_ORIGIN` rather than an invitation to add sections or segmented output.

`assemblyStart` remembers the selected start address so staged offsets can be related back to final addresses and so the final copy knows where to begin.

## Local-label scope

The local-label rule is deliberately small:

> `.name` belongs to the most recent non-local label.

`currentScope` is one byte. Each global label increments it; local names store that byte in their symbol entry. Scope zero means “no current local scope” and is also the scope used for ordinary names.

The counter therefore supports **255 global label scopes** in one assembly. A wrap back to zero is an explicit scope error.

This limit is a visible consequence of the chosen representation, not a hidden defect requiring a larger scope framework.

## Streaming source and includes

`ass/source.asm` talks directly to the C64 KERNAL. There is no filesystem abstraction.

Only one source line is resident at a time. Included files remain open on a fixed set of logical file numbers so a child can reach EOF and the parent can resume at its existing device position.

The nesting bound is explicit:

```text
SOURCE_MAX_DEPTH = 4
```

which means the root plus four nested includes.

EOF state is stored per depth in `sourceEofPending`. This matters because a parent can already have observed end-of-information on the same line that opened its final include. One global EOF flag would lose that parent state while the child was being read.

Path handling is similarly narrow. The standalone assembler optionally prefixes local names with one configured directory and understands the `../` form needed to reach the shared `dis/` files from the production `ass/` tree. It is intentionally not a path normalizer or include-search system.

## Standalone assembler memory contract

`ass/ass.asm` is the standalone native body. Tiny wrappers place the same body at different addresses:

```text
ass/ass_4000.asm -> assembler A at $4000
ass/ass_0800.asm -> generated assembler B at $0800
```

The caller describes one job in six bytes at `$3000`:

```text
$3000/$3001  pointer to filename
$3002        filename length
$3003/$3004  default target address
$3005        returned ASSEMBLE_* status
```

The standalone body then installs a fixed workspace:

```text
$3100          include/path scratch buffer
$3200          256-byte source line buffer
$6000-$9fff    staged output + downward-growing exceptional fixups
$a000-$cfff    symbol entries + downward-growing owned names
```

The symbol area deliberately uses RAM under the BASIC ROM; `assemblerEntry` selects a C64 memory configuration with BASIC hidden while KERNAL and I/O remain visible, then restores the caller's original `$01` value.

The target program, running assembler, command block, line/path buffers, staging area, and symbol area must be chosen so they do not overlap in a way that destroys live state. The self-host test demonstrates one concrete safe geometry: assembler A executes at `$4000`, builds assembler B at `$0800`, and uses the fixed workspaces above.

There is no allocator mediating these regions. The addresses are part of the implementation contract and part of what makes the memory use easy to inspect.

## Module map

Once the flow above is understood, the source files divide naturally:

| File | Machine-level responsibility |
| --- | --- |
| `ass/scanner.asm` | Find the next source lexeme without copying it. |
| `ass/parser.asm` | Return one transient statement name/argument view. |
| `ass/instruction.asm` | Interpret 6502 operand punctuation and map mnemonic + mode through shared metadata. |
| `ass/value.asm` | Reduce the tiny value grammar to either a fixed value or one unresolved-symbol recipe. |
| `ass/symbols.asm` | Own surviving names, values/scopes, and ordinary 16-bit reference chains. |
| `ass/representation.asm` | Stage bytes, store exceptional fixups, resolve branches, and commit the final image. |
| `ass/data.asm` | Implement the three bare data operations using the same value and staging machinery. |
| `ass/source.asm` | Read one C64 source line at a time and manage the bounded include channels. |
| `ass/assembler.asm` | Orchestrate statement semantics and the assembly lifetime. |
| `ass/ass.asm` | Provide the standalone command block and fixed C64 workspace geometry. |

These are source-file boundaries, not a claim that every conceptual compiler stage needs a persistent representation between them.

## In context: three native C64 assembler designs

nanoc is not trying to reproduce an older C64 assembler. But comparing it with contemporary tools is useful because all of them had to answer the same physical questions: where does source live, how much machinery stays resident, and what boundary exists between writing code and turning it into bytes?

The answers were strikingly different.

| System | Main design choice | What that makes simple |
| --- | --- | --- |
| Commodore Macro Assembler Development System (1982) | Separate `EDITOR64` and `ASSEMBLER64` programs, with loaders, monitors, and other tools around them. | Editing and assembly do not have to coexist as one resident program. Source files form a real boundary between tools. |
| Supermon64 (1983) | Put a small assembler inside a machine-language monitor. | Assembly stays extremely close to live machine memory: inspect, alter, assemble, disassemble, run. |
| Turbo Assembler (1985), later developed into Turbo Macro Pro | Integrate editor and assembler into one fast native development environment. | The edit/assemble/test loop becomes immediate because the development environment owns both source editing and assembly. |
| nanoc | Keep the editor outside the assembler, stream source one line at a time, and immediately reduce each line to final-size bytes plus only unavoidable unresolved state. | The assembler can handle a source tree much larger than its line buffer without retaining the source or constructing a second representation of it. |

### Commodore MADS: separation embodied as programs

Commodore's own **Macro Assembler Development System** is the clearest contrast with a modern tendency to think of “editor”, “parser”, and “assembler” as modules inside one process. Its package literally supplied separate programs, including `EDITOR64`, `ASSEMBLER64`, loaders, monitors, and a cross-reference utility.

That division makes sense on the C64. The editor can spend memory on editing; the assembler can spend memory on assembly. Persistent source on disk is the interface between them.

nanoc has a similar external boundary but takes it further inside the assembler: once `source.asm` has delivered a line, the source itself is disposable. `parser.asm` exposes temporary views, then the assembler turns what it can into bytes before the line buffer is reused. Conceptual separation does not require a persistent token or syntax representation.

### Supermon64: assembly as direct machine interaction

Jim Butterfield's **Supermon64** is a different answer. It is principally a machine-language monitor: inspect and alter memory/registers, disassemble code, and assemble instructions directly into memory.

For that job, a project-wide symbolic source representation would be beside the point. The monitor's assembler is useful precisely because it is close to the memory being inspected and changed.

nanoc shares that preference for machine-visible state, but it solves a larger source-assembly problem. Labels, includes, and self-assembly mean some information genuinely must survive after a line disappears. The design question is therefore not “can all state be avoided?” but “what is the minimum state that must survive?”

### Turbo Assembler/TMP: native integration

**Turbo Assembler**, introduced in 1985 and later the ancestor of **Turbo Macro Pro**, takes the opposite product boundary from MADS: editor and assembler are integrated into a rapid native C64 development environment.

That is an excellent design when the goal is to make the whole edit/assemble/test cycle pleasant on the machine. nanoc deliberately has a narrower goal. It is an assembler component on the way to a C compiler, not an editor or IDE, so editor state earns no space in its runtime design.

The contrast is useful because it prevents a false historical lesson. A 64 KB machine does **not** dictate one “correct” assembler architecture. Supermon, MADS, Turbo Assembler, and nanoc all make different trade-offs because they own different jobs.

What *is* era-appropriate across them is the habit of making every resident structure justify itself. nanoc's operand-byte reference chain belongs in that tradition: the two bytes already exist and have no final value yet, so they carry the unresolved-reference link until the moment they become the operand itself.

The lesson for this project is not to imitate 1980s source code. It is to keep asking the same question those programs had to answer visibly:

> **What does this byte of state buy us?**

Historical references:

- [Commodore 64 Macro Assembler Development System manual](https://www.lyonlabs.org/commodore/onrequest/mads.pdf)
- [Supermon64, Jim Butterfield, COMPUTE!, January 1983](https://www.atarimagazines.com/compute/issue32/082_1_SUPERMON_64.php)
- [Turbo Macro Pro: history and genealogy of Turbo Assembler](https://turbo.style64.org/docs/about-turbo-macro-pro-c64-assemblers)

## What is deliberately not here

The assembler currently has no:

- persistent token stream;
- assembler AST;
- generic assembler IR;
- generic relocation table;
- object-file format;
- linker or section model;
- heap allocator;
- layout-relaxation loop;
- forward-constant dependency solver;
- arbitrary-depth include structure;
- general expression parser.

These are not omitted because nanoc is trying to imitate a larger assembler badly. They are absent because the current language and C64 implementation do not need them.

When a simpler machine-level representation solves the actual problem, adding a conventional abstraction would make this project harder to learn from.

## What self-hosting proves

`ass/test_selfhost.asm` turns the architecture into an integration proof:

```text
vasm
  |
  v
assembler A at $4000
  |
  | assembles the real ass/ass_0800.asm include closure
  v
assembler B at $0800
  |
  | B itself executes
  | B assembles ass/selfhost_smoke.asm
  v
A9 2A 8D 20 D0 60
```

The expected bytes are:

```asm
lda #$2a
sta $d020
rts
```

The test does **not** require assembler B to be byte-for-byte identical to vasm's output. It proves the more useful property: nanoc's assembler can build an executable copy of itself, and that generated copy can correctly assemble known source.

For how that proof is executed under VICE and reported to CI, see [Native testing and CI](testing.md).