.section .multiboot, "a"
.align 4

/* Multiboot v1 header so GRUB/QEMU can load us */
.set ALIGN,    1<<0
.set MEMINFO,  1<<1
.set FLAGS, ALIGN | MEMINFO
.set MAGIC, 0x1BADB002
.set CHECKSUM, -(MAGIC + FLAGS)

.long MAGIC
.long FLAGS
.long CHECKSUM

.section .text
.global start
.global _start
.type start, @function
.type _start, @function
_start:
start:
    cli
    /* Early debug: write a byte to QEMU debugcon (0xE9) */
    mov $0xE9, %dx
    mov $'B', %al
    out %al, %dx
    /* Set up a temporary stack */
    mov $stack_top, %esp

    /* Per Multiboot, EAX=magic, EBX=mbi pointer. Pass as C args */
    push %ebx
    push %eax
    call kmain

.hang:
    cli
    hlt
    jmp .hang

.section .bss
.align 16
 .global stack_top
 .global stack_bottom
stack_bottom:
    .space 16384
stack_top:

.section .text
.global reload_segments
.type reload_segments, @function
reload_segments:
    /* Load data segments with selector 0x10, then far jump to reload CS (0x08) */
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss
    ljmp $0x08, $reload_cs
reload_cs:
    ret

/* Helper: load GDT with pointer passed as arg */
.global load_gdt
.type load_gdt, @function
load_gdt:
    mov 4(%esp), %eax
    lgdt (%eax)
    ret

/* Helper: load IDT with pointer passed as arg */
.global load_idt
.type load_idt, @function
load_idt:
    mov 4(%esp), %eax
    lidt (%eax)
    ret

/* Helper: enable interrupts */
.global enable_interrupts
.type enable_interrupts, @function
enable_interrupts:
    sti
    ret

.global cpu_halt
.type cpu_halt, @function
cpu_halt:
    hlt
    ret

.global set_cr3
.type set_cr3, @function
set_cr3:
    mov 4(%esp), %eax
    mov %eax, %cr3
    ret

.global enable_paging
.type enable_paging, @function
enable_paging:
    mov %cr0, %eax
    or $0x80000000, %eax
    mov %eax, %cr0
    ret

.global flush_tlb
.type flush_tlb, @function
flush_tlb:
    mov %cr3, %eax
    mov %eax, %cr3
    ret

.global read_cr2
.type read_cr2, @function
read_cr2:
    mov %cr2, %eax
    ret

.global read_cr0
.type read_cr0, @function
read_cr0:
    mov %cr0, %eax
    ret

.global read_cr3
.type read_cr3, @function
read_cr3:
    mov %cr3, %eax
    ret

.global read_cr4
.type read_cr4, @function
read_cr4:
    mov %cr4, %eax
    ret

.global read_ss
.type read_ss, @function
read_ss:
    xor %eax, %eax
    mov %ss, %ax
    ret

.global read_ds
.type read_ds, @function
read_ds:
    xor %eax, %eax
    mov %ds, %ax
    ret

/* Enable SSE/XMM usage in ring0: set CR0.MP, clear CR0.EM, set CR4.OSFXSR|OSXMMEXCPT, init FPU */
.global enable_sse
.type enable_sse, @function
enable_sse:
    /* CR0: set MP (bit1), clear EM (bit2) */
    mov %cr0, %eax
    or $0x2, %eax       /* MP */
    and $~0x4, %eax     /* ~EM */
    mov %eax, %cr0
    /* CR4: set OSFXSR (bit9) and OSXMMEXCPT (bit10) */
    mov %cr4, %eax
    or $0x600, %eax
    mov %eax, %cr4
    /* Initialize FPU/SSE */
    fninit
    sub $4, %esp
    movl $0x1F80, (%esp)  /* default MXCSR */
    ldmxcsr (%esp)
    add $4, %esp
    ret

.global load_tr
.type load_tr, @function
load_tr:
    mov 4(%esp), %ax
    ltr %ax
    ret

.global enter_user_mode
.type enter_user_mode, @function
/* void enter_user_mode(uint32_t entry, uint32_t user_stack, uint16_t user_ds, uint16_t user_cs) */
enter_user_mode:
    push %ebp
    mov %esp, %ebp
    mov 8(%ebp), %eax      /* entry */
    mov 12(%ebp), %edx     /* user_stack */
    mov 16(%ebp), %cx      /* user_ds */
    mov 20(%ebp), %bx      /* user_cs */
    /* Load user data segments while in ring0 */
    mov %cx, %ds
    mov %cx, %es
    mov %cx, %fs
    mov %cx, %gs
    /* Zero-extend selectors to 32-bit before pushing 32-bit iret frame */
    movzwl 16(%ebp), %ecx   /* ECX = user_ds (zero-extended) */
    movzwl 20(%ebp), %ebx   /* EBX = user_cs (zero-extended) */
    /* Build iret frame (32-bit): EIP, CS, EFLAGS, ESP, SS */
    push %ecx               /* SS = user_ds (32-bit push) */
    push %edx               /* ESP */
    pushf
    orl $0x200, (%esp)      /* ensure IF set */
    push %ebx               /* CS = user_cs (32-bit push) */
    push %eax               /* EIP = entry */
    iret
