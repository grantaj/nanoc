# `nanoc0` bootstrap I/O

The hand-written Phase 1 compiler deliberately assumes two IEC disk devices:

```text
device 8: Nano C source input
device 9: generated ass source output
```

For example, the bootstrap flow is conceptually:

```text
8:ASS.C  ->  nanoc0  ->  9:ASS.ASM
```

This is a bootstrap-machine assumption, not a Nano C source-language feature. Supporting simultaneous source and generated-output files on one disk device adds C64 file/device behaviour to the compiler without teaching anything useful about compilation. A two-drive setup is simple on real hardware and trivial to reproduce in VICE.

The two drives still share the C64's single IEC bus. `nanoc0` therefore keeps one byte of real machine state recording whether the bus is currently selected for source input or generated output. When direction changes, it returns the bus to neutral with `CLRCHN` and then selects the appropriate open logical file with `CHKIN` or `CHKOUT`. Steady input remains a stream of `CHRIN` calls; steady output remains a stream of `CHROUT` calls.

There is no compiler I/O buffer and no general device abstraction. Source input remains streaming and generated assembler is written as it is produced.

Single-drive compilation is intentionally outside the Phase 1 bootstrap contract. It can be reconsidered after self-hosting if there is concrete value in supporting it.
