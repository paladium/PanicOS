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
const mb = @import("multiboot.zig");
const elf = @import("elf.zig");

extern fn outb(port: u16, value: u8) callconv(.C) void;
extern fn cpu_halt() callconv(.C) void;
extern fn enable_interrupts() callconv(.C) void;
extern fn enable_sse() callconv(.C) void;
extern fn enter_user_mode(entry: u32, user_stack: u32, user_ds: u16, user_cs: u16) callconv(.C) void;
extern fn flush_tlb() callconv(.C) void;

pub export fn kmain(multiboot_magic: u32, multiboot_info: usize) callconv(.C) noreturn {
    _ = multiboot_magic;
    mb.set_mbi(multiboot_info);

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
    // Always start in the kernel shell; it can list and run modules on demand
    shell.run();
}

pub export fn on_user_exit() callconv(.C) noreturn {
    // Tear down user mappings to allow clean re-run of programs
    paging.clear_user_mappings();
    logger.log(.info, "returned to shell");
    shell.run();
}
