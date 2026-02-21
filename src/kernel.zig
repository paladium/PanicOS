const DBGPORT: u16 = 0xE9; // QEMU debugcon
const logger = @import("logger.zig");
const vga = @import("vga.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const intr = @import("interrupts.zig");
const paging = @import("paging.zig");
const tss = @import("tss.zig");
const user = @import("user.zig");
const shell = @import("shell.zig");

extern fn outb(port: u16, value: u8) callconv(.C) void;
extern fn cpu_halt() callconv(.C) void;
extern fn enable_interrupts() callconv(.C) void;
extern fn enable_sse() callconv(.C) void;

pub export fn kmain(multiboot_magic: u32, multiboot_info: usize) callconv(.C) noreturn {
    _ = multiboot_magic;
    _ = multiboot_info;

    // Enable SSE/XMM so Zig generated code can use it safely
    enable_sse();
    logger.init();
    gdt.init();
    idt.load();
    intr.pic_remap();
    intr.pit_init(10);
    intr.keyboard_enable();
    // Enable interrupts
    enable_interrupts();

    logger.log(.info, "PanicOS initialized");
    logger.log(.info, "Hello, world from PanicOS!");
    // Setup paging and TSS
    paging.enable();
    tss.init();
    // Run a simple kernel shell for now
    shell.run();
}
