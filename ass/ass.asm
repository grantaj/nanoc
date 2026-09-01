;;; ass.asm
;;;
;;; Standalone native assembler body. The origin is supplied by a tiny wrapper
;;; such as ass_4000.asm or ass_0800.asm so one copy can assemble another
;;; without overwriting itself.
;;;
;;; The caller describes one job in six bytes at $3000:
;;;   $3000/$3001  pointer to filename
;;;   $3002        filename length
;;;   $3003/$3004  default target address
;;;   $3005        returned ASSEMBLE_* status
;;;
;;; Everything else is fixed, caller-visible C64 memory geometry. There is no
;;; allocator: the path buffer, line buffer, symbol arenas, and staged
;;; representation occupy explicit non-overlapping ranges.
;;;
;;; Assembly-lifetime names append from $a000 through $ccff, then continue in the
;;; otherwise idle $3300-$3fff pages below the assembler image. Dot-prefixed names
;;; for the current global-label scope have three fixed pages at $cd00-$cfff; they
;;; grow downward from $d000 and are discarded by rewinding one pointer at the
;;; next global label. The three-page capacity is a direct fixed C64 budget; two
;;; pages were measured at 511/512 bytes while assembling generated Nano C output.
;;; The three ranges have explicit lifetimes and boundaries; none is dynamically
;;; allocated.
;;; ass selects the normal C64 mapping with BASIC hidden and KERNAL/I/O visible
;;; while it runs, then restores the caller's original $01 value.

	include "zp.inc"

ASSEMBLER_COMMAND_NAME   = $3000
ASSEMBLER_COMMAND_LENGTH = $3002
ASSEMBLER_COMMAND_TARGET = $3003
ASSEMBLER_COMMAND_STATUS = $3005

ASSEMBLER_PATH_BUFFER          = $3100
ASSEMBLER_LINE_BUFFER          = $3200
ASSEMBLER_SYMBOL_OVERFLOW      = $3300
ASSEMBLER_SYMBOL_OVERFLOW_END  = $4000
ASSEMBLER_SYMBOLS              = $a000
ASSEMBLER_SYMBOLS_END          = $cd00
ASSEMBLER_LOCAL_SYMBOLS        = $cd00
ASSEMBLER_LOCAL_SYMBOLS_END    = $d000
ASSEMBLER_STAGING              = $6000
ASSEMBLER_STAGING_END          = $a000
SELFHOST_SOURCE_DIRECTORY_LENGTH = 4

;;; assemblerEntry
;;; Configure the fixed workspaces, copy the small command block into the
;;; assembler's normal inputs, assemble one file from device 8, store/return the
;;; ASSEMBLE_* status. The self-host job mounts the repository root, so local
;;; includes are explicitly rooted at ASS/ below.
assemblerEntry:
	lda $01
	sta assemblerMemoryConfig
	lda #$36			; BASIC out, KERNAL and I/O in
	sta $01

	lda #<ASSEMBLER_SYMBOLS
	sta symbolTableStart
	lda #>ASSEMBLER_SYMBOLS
	sta symbolTableStart+1
	lda #<ASSEMBLER_SYMBOLS_END
	sta symbolTableLimit
	lda #>ASSEMBLER_SYMBOLS_END
	sta symbolTableLimit+1

	lda #<ASSEMBLER_LOCAL_SYMBOLS
	sta localSymbolTableStart
	lda #>ASSEMBLER_LOCAL_SYMBOLS
	sta localSymbolTableStart+1
	lda #<ASSEMBLER_LOCAL_SYMBOLS_END
	sta localSymbolTableLimit
	lda #>ASSEMBLER_LOCAL_SYMBOLS_END
	sta localSymbolTableLimit+1

	lda #<ASSEMBLER_SYMBOL_OVERFLOW
	sta symbolOverflowStart
	lda #>ASSEMBLER_SYMBOL_OVERFLOW
	sta symbolOverflowStart+1
	lda #<ASSEMBLER_SYMBOL_OVERFLOW_END
	sta symbolOverflowLimit
	lda #>ASSEMBLER_SYMBOL_OVERFLOW_END
	sta symbolOverflowLimit+1

	lda #<ASSEMBLER_STAGING
	sta stagingStart
	lda #>ASSEMBLER_STAGING
	sta stagingStart+1
	lda #<ASSEMBLER_STAGING_END
	sta stagingLimit
	lda #>ASSEMBLER_STAGING_END
	sta stagingLimit+1

	lda ASSEMBLER_COMMAND_NAME
	sta sourceName
	lda ASSEMBLER_COMMAND_NAME+1
	sta sourceName+1
	lda ASSEMBLER_COMMAND_LENGTH
	sta sourceNameLength
	lda #$08
	sta sourceDevice
	lda #<ASSEMBLER_LINE_BUFFER
	sta sourceLineBuffer
	lda #>ASSEMBLER_LINE_BUFFER
	sta sourceLineBuffer+1
	lda #<selfhostSourceDirectory
	sta sourceDirectory
	lda #>selfhostSourceDirectory
	sta sourceDirectory+1
	lda #SELFHOST_SOURCE_DIRECTORY_LENGTH
	sta sourceDirectoryLength
	lda #<ASSEMBLER_PATH_BUFFER
	sta sourcePathBuffer
	lda #>ASSEMBLER_PATH_BUFFER
	sta sourcePathBuffer+1
	lda ASSEMBLER_COMMAND_TARGET
	sta assemblyPtr
	lda ASSEMBLER_COMMAND_TARGET+1
	sta assemblyPtr+1

	jsr assembleFile
	sta ASSEMBLER_COMMAND_STATUS
	lda assemblerMemoryConfig
	sta $01
	lda ASSEMBLER_COMMAND_STATUS
	rts

assemblerMemoryConfig:
	byte 0

;;; Self-host source-tree configuration, not assembler language semantics.
;;; The repository root is mounted as the C64 filesystem; local includes live in
;;; ASS/, while ../dis/... deliberately drops that prefix.
selfhostSourceDirectory:
	byte 'A','S','S','/'

	include "parser.asm"
	include "instruction.asm"
	include "symbols.asm"
	include "value.asm"
	include "assembler.asm"
