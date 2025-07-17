;=======================
; kernal.inc — C64 KERNAL Jump Table with API Annotations
; Compatible with vasm oldstyle syntax
;=======================

;===== System Initialization =====

INIT       = $FF81  ; Init system (called after RESET)
;  Initializes vectors, I/O, memory, etc.

IOINIT     = $FF84  ; Initialize I/O devices
;  Sets up CIA, screen, keyboard

RAMTAS     = $FF87  ; RAM test and setup
;  Sets RAMTOP/START; zeroes memory

RESTOR     = $FF8A  ; Restore default vectors
;  Restores IRQ, BRK, input/output vectors

VECTOR     = $FF8D  ; Setup vectors
;  Installs jump table to RAM vectors

SETMSG     = $FF90  ; Set message flag
;  A = 0: suppress LOAD/SAVE messages
;    = 1: enable LOAD/SAVE messages

SECOND     = $FF93  ; Send secondary address on serial bus
;  A = secondary address (0–31)

TKSA       = $FF96  ; Send TALK/secondary address
;  A = secondary address

MEMTOP     = $FF99  ; Set/get top of memory
;  On entry: A != 0 => set memory top from (X/Y)
;  X/Y = new top (X = low, Y = high)
;  On exit: X/Y = current top

MEMBOT     = $FF9C  ; Set/get bottom of memory
;  Same interface as MEMTOP

SCNKEY     = $FF9F  ; Scan keyboard
;  Updates keyboard buffer, SHIFT flags

SETTMO     = $FFA2  ; Set serial bus timeout
;  A = 0: enable timeout
;    = 1: disable timeout

;===== Serial Bus I/O =====

ACPTR      = $FFA5  ; Read byte from serial bus
;  Returns: A = byte read

CIOUT      = $FFA8  ; Write byte to serial bus
;  A = byte to write

UNTALK     = $FFAB  ; End TALK on serial bus

UNLSN      = $FFAE  ; End LISTEN on serial bus

LISTEN     = $FFB1  ; Send LISTEN address
;  A = device number (0–31)

TALK       = $FFB4  ; Send TALK address
;  A = device number (0–31)

READST     = $FFB7  ; Read status byte
;  Returns: A = status (bitfield)

;===== File Handling =====

SETLFS     = $FFBA  ; Set Logical File Parameters
;  A = Logical file #
;  X = Device #
;  Y = Secondary address

SETNAM     = $FFBD  ; Set Filename
;  A = Length of filename
;  X/Y = Pointer to filename string (X = low, Y = high)

OPEN       = $FFC0  ; Open file
;  Uses params from SETLFS and SETNAM

CLOSE      = $FFC3  ; Close file
;  A = Logical file #

CHKIN      = $FFC6  ; Set input channel
;  A = Logical file #

CHKOUT     = $FFC9  ; Set output channel
;  A = Logical file #

CLRCHN     = $FFCC  ; Clear all I/O channels

CHRIN      = $FFCF  ; Read char from input
;  Returns: A = character

CHROUT     = $FFD2  ; Output character
;  A = character to output

;===== File Load/Save =====

LOAD       = $FFD5  ; Load file to memory
;  A = 0: verify only
;  A = 1: load
;  X/Y = start address (X = low, Y = high) if SA=0
;  Returns: A = status, Z=1 = success
;           X/Y = end address

SAVE       = $FFD8  ; Save memory to file
;  A = Logical file #
;  X/Y = start address
;  (C/D) = end address

;===== System Clock =====

SETTIM     = $FFDB  ; Set jiffy clock
;  X/Y/A = 24-bit time value (jiffies since power-on)

RDTIM      = $FFDE  ; Read jiffy clock
;  Returns: X/Y/A = current time

UDTIM      = $FFEA  ; Update jiffy clock
;  Called from IRQ — advances system clock

;===== Input Handling =====

STOP       = $FFE1  ; Check STOP key
;  Returns: Z = 0 if STOP key pressed

GETIN      = $FFE4  ; Get char from input buffer
;  Returns: A = char, or 0 if none

CLALL      = $FFE7  ; Close all files and clear channels

;===== Screen and Cursor =====

SCREEN     = $FFED  ; Get screen memory base
;  Returns: X/Y = base address of screen RAM

PLOT       = $FFF0  ; Get/set cursor position
;  On entry: A = 0 to read, A = 1 to set
;  For set: X = X pos, Y = Y pos
;  For get: Returns X/Y = current pos

IOBASE     = $FFF3  ; Get I/O base address
;  Returns: A = page number of I/O base (usually $D0)

