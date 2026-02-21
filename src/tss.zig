const gdt = @import("gdt.zig");

pub const TSS = packed struct {
    prev_tss: u16, prev_tss_hi: u16,
    esp0: u32, ss0: u16, ss0_hi: u16,
    esp1: u32, ss1: u16, ss1_hi: u16,
    esp2: u32, ss2: u16, ss2_hi: u16,
    cr3: u32, eip: u32, eflags: u32,
    eax: u32, ecx: u32, edx: u32, ebx: u32,
    esp: u32, ebp: u32, esi: u32, edi: u32,
    es: u16, es_hi: u16, cs: u16, cs_hi: u16,
    ss: u16, ss_hi: u16, ds: u16, ds_hi: u16,
    fs: u16, fs_hi: u16, gs: u16, gs_hi: u16,
    ldt: u16, ldt_hi: u16,
    trap: u16, iomap_base: u16,
};

var tss: TSS = .{ .prev_tss = 0, .prev_tss_hi = 0,
    .esp0 = 0, .ss0 = 0, .ss0_hi = 0,
    .esp1 = 0, .ss1 = 0, .ss1_hi = 0,
    .esp2 = 0, .ss2 = 0, .ss2_hi = 0,
    .cr3 = 0, .eip = 0, .eflags = 0,
    .eax = 0, .ecx = 0, .edx = 0, .ebx = 0,
    .esp = 0, .ebp = 0, .esi = 0, .edi = 0,
    .es = 0, .es_hi = 0, .cs = 0, .cs_hi = 0,
    .ss = 0, .ss_hi = 0, .ds = 0, .ds_hi = 0,
    .fs = 0, .fs_hi = 0, .gs = 0, .gs_hi = 0,
    .ldt = 0, .ldt_hi = 0, .trap = 0, .iomap_base = @sizeOf(TSS), };

extern var stack_top: u8; // from boot.S

pub fn init() void {
    tss.ss0 = gdt.KERNEL_DS;
    tss.esp0 = @as(u32, @truncate(@intFromPtr(&stack_top)));
    gdt.set_tss(@as(u32, @truncate(@intFromPtr(&tss))), @as(u32, @truncate(@sizeOf(TSS)-1)));
}
