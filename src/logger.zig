const vga = @import("vga.zig");

extern fn outb(port: u16, value: u8) callconv(.C) void;
extern fn inb(port: u16) callconv(.C) u8;

const COM1: u16 = 0x3F8;

fn serial_is_transmit_empty() bool { return (inb(COM1 + 5) & 0x20) != 0; }
fn serial_write_byte(b: u8) void {
    var tries: usize = 0;
    while (!serial_is_transmit_empty() and tries < 1_000_000) : (tries += 1) {}
    outb(COM1, b);
}

fn serial_write(buf: []const u8) void { var i: usize = 0; while (i < buf.len) : (i += 1) serial_write_byte(buf[i]); }

pub fn serial_init() void {
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x80);
    outb(COM1 + 0, 0x01);
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x03);
    outb(COM1 + 2, 0xC7);
    outb(COM1 + 4, 0x0B);
}

pub const Level = enum { trace, debug, info, warn, err };

fn level_tag(l: Level) []const u8 {
    return switch (l) {
        .trace => "[TRACE] ",
        .debug => "[DEBUG] ",
        .info => "[INFO ] ",
        .warn => "[WARN ] ",
        .err => "[ERROR] ",
    };
}

pub fn init() void {
    serial_init();
    vga.init();
}

pub fn log(l: Level, msg: []const u8) void {
    const tag = level_tag(l);
    vga.write(tag); vga.write(msg); vga.write("\r\n");
    serial_write(tag); serial_write(msg); serial_write("\r\n");
}

pub fn hex8(x: u8) [2]u8 {
    const hexd = "0123456789ABCDEF";
    return .{ hexd[(x >> 4) & 0xF], hexd[x & 0xF] };
}

pub fn log_hex(label: []const u8, data: []const u8) void {
    vga.write(label); vga.write(": ");
    serial_write(label); serial_write(": ");
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        const h = hex8(data[i]);
        vga.write_byte(h[0]); vga.write_byte(h[1]); vga.write_byte(' ');
        serial_write_byte(h[0]); serial_write_byte(h[1]); serial_write_byte(' ');
    }
    vga.write("\r\n"); serial_write("\r\n");
}

// Raw write to both outputs without tags
pub fn write_raw(buf: []const u8) void {
    vga.write(buf);
    serial_write(buf);
}
