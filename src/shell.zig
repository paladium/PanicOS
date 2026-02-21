const logger = @import("logger.zig");
const intr = @import("interrupts.zig");

extern fn cpu_halt() callconv(.C) void;

fn prompt() void {
    logger.write_raw("> ");
}

fn is_space(c: u8) bool { return c == ' ' or c == '\t'; }

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and is_space(s[start])) start += 1;
    var end = s.len;
    while (end > start and is_space(s[end-1])) end -= 1;
    return s[start..end];
}

fn handle_line(line: []const u8) void {
    const t = trim(line);
    if (t.len == 0) return;
    // Find first space to split command and args
    var i: usize = 0;
    while (i < t.len and !is_space(t[i])) : (i += 1) {}
    const cmd = t[0..i];
    const args: []const u8 = if (i < t.len) trim(t[i..]) else t[i..i];
    if (cmd.len == 4 and cmd[0]=='e' and cmd[1]=='c' and cmd[2]=='h' and cmd[3]=='o') {
        // echo: print args and newline
        if (args.len != 0) logger.write_raw(args);
        logger.write_raw("\r\n");
    } else {
        logger.write_raw("Unknown command: ");
        logger.write_raw(cmd);
        logger.write_raw("\r\n");
    }
}

pub fn run() noreturn {
    logger.log(.info, "Shell ready (type: echo <text>)");
    var buf: [128]u8 = undefined;
    var len: usize = 0;
    prompt();
    while (true) {
        if (intr.kbd_getch()) |ch| {
            switch (ch) {
                '\r', '\n' => {
                    logger.write_raw("\r\n");
                    handle_line(buf[0..len]);
                    len = 0;
                    prompt();
                },
                0x08 => {
                    if (len > 0) {
                        len -= 1;
                        // Erase last char visually: BS, space, BS
                        var bs: [3]u8 = .{ 0x08, ' ', 0x08 };
                        logger.write_raw(bs[0..]);
                    }
                },
                else => {
                    if (len + 1 < buf.len) {
                        buf[len] = ch; len += 1;
                        var tmp: [1]u8 = .{ch};
                        logger.write_raw(tmp[0..]);
                    }
                },
            }
        } else {
            cpu_halt();
        }
    }
}
