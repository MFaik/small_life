BITS 64
; i just copy pasted the whole elf header
; maybe it can be made shorter (TODO?)
        org 0x400000

ehdr:                              ; ELF header (64 bytes)
        db  0x7F, "ELF", 2,1,1,0   ; ELF magic
        times 8 db 0               ; Padding
        dw  2                      ; Type: EXEC
        dw  0x3E                   ; Machine: x86_64
        dd  1                      ; Version
        dq  _start                 ; Entry point
        dq  phdr - $$              ; Program header offset
        dq  0                      ; Section header offset
        dd  0                      ; Flags
        dw  ehdrsize               ; ELF header size
        dw  phdrsize               ; Program header entry size
        dw  1                      ; Number of program headers
        dw  0                      ; Section header entry size
        dw  0                      ; Number of section headers
        dw  0                      ; Section header string table index

ehdrsize equ $ - ehdr

phdr:                           ; Program header (56 bytes)
        dd  1                      ; Type: LOAD
        dd  7                      ; Flags: RWX
        dq  0                      ; Offset
        dq  0x400000               ; Virtual addr
        dq  0x400000               ; Physical addr
        dq  filesize               ; File size
        dq  filesize               ; Mem size
        dq  0x1000                 ; Align

phdrsize equ $ - phdr

; ----------- CODE STARTS HERE ------------

SYS_WRITE         equ 1
SYS_OPEN          equ 2
SYS_MMAP          equ 9
SYS_RT_SIGACTION  equ 13
SYS_IOCTL         equ 16
SYS_EXIT          equ 60
SYS_CLOCK_GETTIME equ 228

STACK_SCREEN_WIDTH equ 148
STACK_SCREEN_HEIGHT equ 152
STACK_SCREEN_MEM equ 156

; TODO add a proper timing system
; STACK_TIME_CURRENT equ 140 ; current frame (8 bytes)
; STACK_TIME_LAST    equ 144 ; previous frame (8 bytes)

_start:
    ; make stack as big as the screen info ioctl return
        sub rsp, 160

    ; open(rdi, rsi, rdx)
    ; open(*filename, flags, mode)
    ; open /dev/tty
        mov rax, SYS_OPEN
        mov rdi, tty_path
        mov rsi, 2               ; O_RDWR
        xor rdx, rdx
        syscall
        mov r12, rax ; tty_fd
    ; ioctl(TTY, KDSETMODE, KD_GRAPHICS)
        mov rax, SYS_IOCTL
        mov rdi, r12 ; tty_fd
        mov rsi, 0x4B3A          ; KDSETMODE
        mov rdx, 1               ; KD_GRAPHICS
        syscall

    ; setup signal handler
        mov qword [sigact], _signal_handler
        mov qword [sigact+8], 0x04000000  ; SA_RESTORER flag
        mov qword [sigact+16], _restorer
        mov qword [sigact+24], 0

        mov r15, signals
        mov rcx, 5
_setup_signals:
        mov rax, SYS_RT_SIGACTION
        mov rdi, [r15]         ; Load signal number
        mov rsi, sigact
        xor rdx, rdx
        mov r10, 8
        push rcx
        syscall
        pop rcx
        add r15, 8
        loop _setup_signals

    ; open(rdi, rsi, rdx)
    ; open(*filename, flags, mode)
    ; open /dev/fb0
        mov rax, SYS_OPEN
        mov rdi, fbpath
        mov rsi, 2 ; O_RDWR
        xor rdx, rdx
        syscall
        mov rbx, rax ; rbx = fd
        
    ; ioctl(rdi, rsi, rdx)
    ; ioctl(fd,  cmd, arg)
        mov rax, SYS_IOCTL
        mov rdi, rbx ; rbx = fd
        mov rsi, 0x4600 ; FBIOGET_VSCREENINFO
        mov rdx, rsp
        syscall

        xor r15, r15 ; r15 = 0
        mov r15d, dword [rsp+8] ; screen_width
        xor r14, r14 ; r14 = 0
        mov r14d, dword [rsp+12] ; screen_height
        
    ; mmap(rdi,  rsi, rdx,  r10,   r8, r9   )
    ; mmap(addr, len, prot, flags, fd, pgoff)
        mov rsi, r15
        imul rsi, r14 ; rsi = width * height
        shl rsi, 2

        mov rax, SYS_MMAP
        xor rdi, rdi
        mov rdx, 3 ; PROT_WRITE | PROT_READ
        mov r10, 1 ; MAP_SHARED
        mov r8, rbx ; rbx = fd
        xor r9, r9
        syscall
        mov r11, rax ; r11 = map of frame buffer

    ; clear screen
        mov rdi, r11
        mov ecx, r15d ; screen_width
        imul ecx, r14d ; screen_width * screen_height
        mov eax, 0xFF000000 ; Black (dead)
        rep stosd

        mov eax, r15d ; screen_width
        mov ebx, r14d ; screen_height
        shr eax, 1 ; center_x = width/2
        shr ebx, 1 ; center_y = height/2
        mov rdi, r11
        mov ecx, ebx
        imul ecx, r15d ; y_offset = center_y * width
        add ecx, eax ; center_offset = y_offset + center_x
        lea rdi, [rdi + rcx*4] ; pixel address

        mov rcx, [rsp + 160 + 16] ; argv[1]
    ;no argument check
        cmp rcx, 0
        je _arg_exit_loop

        xor rbx, rbx
shl r15, 2
_arg_read_loop:
        cmp byte [rcx], 0
        je _arg_exit_loop

        cmp byte [rcx], 10 ; new line
        je _arg_new_line

        cmp byte [rcx], 32 ; space
        je _arg_skip_set_pixel
        mov dword [rdi], 0xFFFFFFFF
    _arg_skip_set_pixel:
        add rcx, 1
        add rdi, 4
        add rbx, 4
        jmp _arg_read_loop
    _arg_new_line: 
        add rcx, 1
        sub rdi, rbx
        add rdi, r15
        xor rbx, rbx ; rbx = 0
        jmp _arg_read_loop
_arg_exit_loop:
shr r15, 2

    ; optimize this maybe? TODO
    ; set padding around the framebuffer to
    ; eliminate border checks on game logic
        sub r15, 2
        sub r14, 2
        imul r14, r15
        
        mov r10, 0xFFFFFFFE ; positive bitmask
        mov r9, 0x00000001 ; negative bitmask

_game_loop:
    ;TODO make a better timing system
        mov rcx, 100000
        _wait_loop:
        nop
        nop
        loop _wait_loop
    ;draw
        xor r10, 3 ; switch the bitmask parity
        xor r9,  3 ; switch the bitmask parity

        mov r13, 0 ; x = 0

        mov rdi, r11 ; rdi = start of fb mapped memory

        mov rcx, r14 ; rcx = length of used fb
_paint_loop:
    ;position counter
        add r13, 1
        cmp r13, r15 ; x < width
        jl _skip_line_reset
    ;line reset
        mov r13, 0 ; x = 0
        add rdi, 8
_skip_line_reset:
        mov rdx, 0 ; neighbour count
        ;TODO reduce the size of neighbour counting
        mov eax, dword [rdi]
        and eax, r9d
        add edx, eax
        mov eax, dword [rdi+4]
        and eax, r9d
        add edx, eax
        mov eax, dword [rdi+8]
        and eax, r9d
        add edx, eax
        mov eax, dword [rdi+r15*4+8]
        and eax, r9d
        add edx, eax
        mov eax, dword [rdi+r15*4+16]
        and eax, r9d
        add edx, eax
        mov eax, dword [rdi+r15*8+16]
        and eax, r9d
        add edx, eax
        mov eax, dword [rdi+r15*8+20]
        and eax, r9d
        add edx, eax
        mov eax, dword [rdi+r15*8+24]
        and eax, r9d
        add edx, eax
        
        mov eax, r9d
        dec eax
        jz _skip_neighbour_shift
        shr edx, 1
_skip_neighbour_shift:
        cmp edx, 3
        je _set_cell
        cmp edx, 2
        je _preserve_cell
_clear_cell:
        and dword [rdi+r15*4+12], r9d
        jmp _skip_cell
_preserve_cell:
        mov edx, dword [rdi+r15*4+12]
        and edx, r9d
        cmp edx, 0
        je _clear_cell
        jnz _set_cell
_set_cell:
        or dword [rdi+r15*4+12], r10d
_skip_cell:

    ;looper
        add rdi, 4
        dec rcx
        jnz near _paint_loop
        jmp _game_loop

_signal_handler:
    mov rax, SYS_IOCTL
    mov rdi, r12 ; rdi = ttyfd
    mov rsi, 0x4B3A ; KDSETMODE
    xor rdx, rdx ; KD_TEXT (0)
    syscall

    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall
; without the restorer the program always crashes (TODO?)
_restorer:
        mov rax, 15              ; SYS_rt_sigreturn
        syscall

fbpath: db "/dev/fb0",0
tty_path: db "/dev/tty", 0
sigact: times 4 dq 0
signals:
        dq 2    ; SIGINT   (Ctrl+C)
        ;dq 15   ; SIGTERM (termination signal)
        dq 3    ; SIGQUIT (Ctrl+\)
        ;dq 1    ; SIGHUP  (terminal disconnect)
        dq 20   ; SIGTSTP (Ctrl+Z)

filesize equ $ - $$ ; for program header
