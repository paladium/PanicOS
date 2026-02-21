.intel_syntax noprefix
.code32
.section .text
.global isr0
.global isr1
.global isr2
.global isr3
.global isr4
.global isr5
.global isr6
.global isr7
.global isr8
.global isr9
.global isr10
.global isr11
.global isr12
.global isr13
.global isr14
.global isr15
.global isr16
.global isr17
.global isr18
.global isr19
.global isr20
.global isr21
.global isr22
.global isr23
.global isr24
.global isr25
.global isr26
.global isr27
.global isr28
.global isr29
.global isr30
.global isr31
.global irq0
.global irq1
.global isr128

.extern isr_dispatch
.extern irq0_handler
.extern irq1_handler
.extern syscall_dispatch_abi

/* Common pattern for exceptions without an error code */
.macro ISR_NOERR n
isr\n:
    /* Save original ESP (points to [EIP,CS,EFLAGS,(UESP,USS)?]) */
    mov edx, esp
    pusha
    push ds
    push es
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    /* push args (cdecl): base_off=0, frame_ptr=edx, err=0, vec=n */
    push 0
    push edx
    push 0
    push \n
    call isr_dispatch
    add esp, 16           /* pop args */
    pop es
    pop ds
    popa
    iretd
.endm

/* Common pattern for exceptions with an error code pushed by CPU */
.macro ISR_HASERR n
isr\n:
    /* Save original ESP (points to [ERR,EIP,CS,EFLAGS,(UESP,USS)?]) */
    mov edx, esp
    mov ecx, [edx]        /* err */
    pusha
    push ds
    push es
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    /* push args (cdecl): base_off=4, frame_ptr=edx, err=ecx, vec=n */
    push 4
    push edx
    push ecx
    push \n
    call isr_dispatch
    add esp, 16           /* pop args */
    pop es
    pop ds
    popa
    add esp, 4            /* drop original CPU error code */
    iretd
.endm

/* Exceptions: some push error codes automatically (8,10-14,17) */
ISR_NOERR 0
ISR_NOERR 1
ISR_NOERR 2
ISR_NOERR 3
ISR_NOERR 4
ISR_NOERR 5
ISR_NOERR 6
ISR_NOERR 7
ISR_HASERR 8
ISR_NOERR 9
ISR_HASERR 10
ISR_HASERR 11
ISR_HASERR 12
ISR_HASERR 13
ISR_HASERR 14
ISR_NOERR 15
ISR_NOERR 16
ISR_HASERR 17
ISR_NOERR 18
ISR_NOERR 19
ISR_NOERR 20
ISR_NOERR 21
ISR_NOERR 22
ISR_NOERR 23
ISR_NOERR 24
ISR_NOERR 25
ISR_NOERR 26
ISR_NOERR 27
ISR_NOERR 28
ISR_NOERR 29
ISR_NOERR 30
ISR_NOERR 31

irq0:
    pusha
    push ds
    push es
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    call irq0_handler
    pop es
    pop ds
    popa
    iretd
irq1:
    pusha
    push ds
    push es
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    call irq1_handler
    pop es
    pop ds
    popa
    iretd

/* int 0x80 syscall entry */
isr128:
    pusha
    /*
     * PUSHAD frame at [esp] after pusha (lower addresses first):
     *   [0]=EDI, [4]=ESI, [8]=EBP, [12]=ESP (orig), [16]=EBX, [20]=EDX, [24]=ECX, [28]=EAX
     * We snapshot user EAX/EBX/ECX/EDX into scratch regs before touching AX for segment loads.
     */
    mov edi, [esp+28]   /* user EAX -> EDI */
    mov ebx, [esp+16]   /* user EBX -> EBX */
    mov esi, [esp+24]   /* user ECX -> ESI */
    mov ebp, [esp+20]   /* user EDX -> EBP */
    /* Switch DS/ES to kernel data (preserve current values) */
    push ds
    push es
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    /* Call Zig syscall handler with (eax, ebx, ecx, edx) via cdecl */
    push ebp            /* EDX */
    push esi            /* ECX */
    push ebx            /* EBX */
    push edi            /* EAX */
    call syscall_dispatch_abi
    add esp, 16
    /* Restore segment registers */
    pop es
    pop ds
    /* Store return value to saved EAX slot so popa returns it to user */
    mov [esp+28], eax
    popa
    iretd
