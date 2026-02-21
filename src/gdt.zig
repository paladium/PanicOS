const std = @import("std");

pub const Descriptor = packed struct(u64) {
    limit_low: u16,
    base_low: u16,
    base_mid: u8,
    access: u8,
    gran: u8,
    base_high: u8,
};

fn make_descriptor(base: u32, limit: u32, access: u8, flags: u8) u64 {
    var desc: u64 = 0;
    desc |= (limit & 0xFFFF);
    desc |= (@as(u64, base & 0xFFFFFF) << 16);
    desc |= (@as(u64, access) << 40);
    desc |= (@as(u64, ((limit >> 16) & 0xF) | ((flags & 0xF) << 4)) << 48);
    desc |= (@as(u64, (base >> 24) & 0xFF) << 56);
    return desc;
}

var gdt: [6]u64 = .{
    0, // null
    make_descriptor(0, 0xFFFFF, 0x9A, 0x0C), // 0x08: kernel code
    make_descriptor(0, 0xFFFFF, 0x92, 0x0C), // 0x10: kernel data
    make_descriptor(0, 0xFFFFF, 0xFA, 0x0C), // 0x18: user code (DPL=3)
    make_descriptor(0, 0xFFFFF, 0xF2, 0x0C), // 0x20: user data (DPL=3)
    0, // TSS placeholder; filled at runtime
};

const GDTR = packed struct {
    limit: u16,
    base: u32,
};

extern fn reload_segments() callconv(.C) void;
extern fn load_gdt(ptr: *const anyopaque) callconv(.C) void;
extern fn load_tr(sel: u16) callconv(.C) void;

pub fn init() void {
    var gdtr = GDTR{ .limit = @intCast(@sizeOf(@TypeOf(gdt)) - 1), .base = @intFromPtr(&gdt) };
    load_gdt(&gdtr);
    // Reload CS/DS/SS via small asm thunk (defined in asm)
    reload_segments();
}

pub const KERNEL_CS: u16 = 0x08;
pub const KERNEL_DS: u16 = 0x10;
pub const USER_CS: u16 = 0x18 | 0x3;
pub const USER_DS: u16 = 0x20 | 0x3;

pub fn set_tss(base: u32, limit: u32) void {
    // 0x28 selector for TSS
    const idx: usize = 5;
    const access: u8 = 0x89; // present | 32-bit TSS (available)
    const flags: u8 = 0x00;
    gdt[idx] = make_descriptor(base, limit, access, flags);
    load_tr(0x28);
}
