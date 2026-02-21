const std = @import("std");

const IDTEntry = packed struct {
    offset_low: u16,
    selector: u16,
    zero: u8,
    type_attr: u8,
    offset_high: u16,
};

const IDTR = packed struct {
    limit: u16,
    base: u32,
};

var idt: [256]IDTEntry = [_]IDTEntry{.{ .offset_low = 0, .selector = 0x08, .zero = 0, .type_attr = 0x8E, .offset_high = 0 }} ** 256;

fn set_gate(i: usize, handler: usize, sel: u16, flags: u8) void {
    idt[i] = .{
        .offset_low = @intCast(handler & 0xFFFF),
        .selector = sel,
        .zero = 0,
        .type_attr = flags,
        .offset_high = @intCast((handler >> 16) & 0xFFFF),
    };
}

extern fn isr0() callconv(.C) void;  // ... exceptions 0..31
extern fn isr1() callconv(.C) void;
extern fn isr2() callconv(.C) void;
extern fn isr3() callconv(.C) void;
extern fn isr4() callconv(.C) void;
extern fn isr5() callconv(.C) void;
extern fn isr6() callconv(.C) void;
extern fn isr7() callconv(.C) void;
extern fn isr8() callconv(.C) void;
extern fn isr9() callconv(.C) void;
extern fn isr10() callconv(.C) void;
extern fn isr11() callconv(.C) void;
extern fn isr12() callconv(.C) void;
extern fn isr13() callconv(.C) void;
extern fn isr14() callconv(.C) void;
extern fn isr15() callconv(.C) void;
extern fn isr16() callconv(.C) void;
extern fn isr17() callconv(.C) void;
extern fn isr18() callconv(.C) void;
extern fn isr19() callconv(.C) void;
extern fn isr20() callconv(.C) void;
extern fn isr21() callconv(.C) void;
extern fn isr22() callconv(.C) void;
extern fn isr23() callconv(.C) void;
extern fn isr24() callconv(.C) void;
extern fn isr25() callconv(.C) void;
extern fn isr26() callconv(.C) void;
extern fn isr27() callconv(.C) void;
extern fn isr28() callconv(.C) void;
extern fn isr29() callconv(.C) void;
extern fn isr30() callconv(.C) void;
extern fn isr31() callconv(.C) void;

extern fn irq0() callconv(.C) void; // PIC remapped IRQ0..IRQ15 to 32..47
extern fn irq1() callconv(.C) void;
extern fn isr128() callconv(.C) void; // syscall gate

pub fn load() void {
    // Exceptions 0..31
    const sel: u16 = 0x08;
    const flags: u8 = 0x8E;
    set_gate(0, @intFromPtr(&isr0), sel, flags);
    set_gate(1, @intFromPtr(&isr1), sel, flags);
    set_gate(2, @intFromPtr(&isr2), sel, flags);
    set_gate(3, @intFromPtr(&isr3), sel, flags);
    set_gate(4, @intFromPtr(&isr4), sel, flags);
    set_gate(5, @intFromPtr(&isr5), sel, flags);
    set_gate(6, @intFromPtr(&isr6), sel, flags);
    set_gate(7, @intFromPtr(&isr7), sel, flags);
    set_gate(8, @intFromPtr(&isr8), sel, flags);
    set_gate(9, @intFromPtr(&isr9), sel, flags);
    set_gate(10, @intFromPtr(&isr10), sel, flags);
    set_gate(11, @intFromPtr(&isr11), sel, flags);
    set_gate(12, @intFromPtr(&isr12), sel, flags);
    set_gate(13, @intFromPtr(&isr13), sel, flags);
    set_gate(14, @intFromPtr(&isr14), sel, flags);
    set_gate(15, @intFromPtr(&isr15), sel, flags);
    set_gate(16, @intFromPtr(&isr16), sel, flags);
    set_gate(17, @intFromPtr(&isr17), sel, flags);
    set_gate(18, @intFromPtr(&isr18), sel, flags);
    set_gate(19, @intFromPtr(&isr19), sel, flags);
    set_gate(20, @intFromPtr(&isr20), sel, flags);
    set_gate(21, @intFromPtr(&isr21), sel, flags);
    set_gate(22, @intFromPtr(&isr22), sel, flags);
    set_gate(23, @intFromPtr(&isr23), sel, flags);
    set_gate(24, @intFromPtr(&isr24), sel, flags);
    set_gate(25, @intFromPtr(&isr25), sel, flags);
    set_gate(26, @intFromPtr(&isr26), sel, flags);
    set_gate(27, @intFromPtr(&isr27), sel, flags);
    set_gate(28, @intFromPtr(&isr28), sel, flags);
    set_gate(29, @intFromPtr(&isr29), sel, flags);
    set_gate(30, @intFromPtr(&isr30), sel, flags);
    set_gate(31, @intFromPtr(&isr31), sel, flags);
    // IRQs
    set_gate(32, @intFromPtr(&irq0), sel, flags);
    set_gate(33, @intFromPtr(&irq1), sel, flags);
    // int 0x80 syscall gate, DPL=3
    idt[128] = .{
        .offset_low = @intCast(@intFromPtr(&isr128) & 0xFFFF),
        .selector = sel,
        .zero = 0,
        .type_attr = 0xEE, // present, DPL=3, 32-bit interrupt gate
        .offset_high = @intCast((@intFromPtr(&isr128) >> 16) & 0xFFFF),
    };

    var idtr = IDTR{ .limit = @intCast(@sizeOf(@TypeOf(idt)) - 1), .base = @intFromPtr(&idt) };
    load_idt(&idtr);
}

extern fn load_idt(ptr: *const anyopaque) callconv(.C) void;
