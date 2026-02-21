ENTRY(_start)

OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i386)

SECTIONS
{
    /* Load kernel at 1 MiB */
    . = 1M;

    .text : ALIGN(4K) {
        /* Place Multiboot header at the start of .text so it lands
           within the first 8KiB of the file. */
        KEEP(*(.multiboot))
        /* Keep all code so the linker GC doesn't drop our entry/startup */
        KEEP(*(.text .text.*))
    }

    .rodata : ALIGN(4K) {
        *(.rodata .rodata.*)
    }

    .data : ALIGN(4K) {
        *(.data .data.*)
    }

    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss .bss.*)
    }

    /* Discard sections we don't need to avoid orphan placement ahead of .text */
    /DISCARD/ : {
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.comment)
        *(.note*)
        *(.debug*)
    }
}
