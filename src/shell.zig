const logger = @import("logger.zig");
const intr = @import("interrupts.zig");
const mb = @import("multiboot.zig");
const elf = @import("elf.zig");
const gdt = @import("gdt.zig");
const user = @import("user.zig");
const paging = @import("paging.zig");
extern fn enter_user_mode(entry: u32, user_stack: u32, user_ds: u16, user_cs: u16) callconv(.C) void;
extern fn flush_tlb() callconv(.C) void;

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
    } else if (cmd.len == 4 and cmd[0]=='h' and cmd[1]=='e' and cmd[2]=='l' and cmd[3]=='p') {
        logger.write_raw("Commands:\r\n");
        logger.write_raw("  help           - show this help\r\n");
        logger.write_raw("  ls|progs       - list available programs\r\n");
        logger.write_raw("  run <name>     - run a program by name\r\n");
        logger.write_raw("  echo <text>    - print text\r\n");
    } else if ((cmd.len == 2 and cmd[0]=='l' and cmd[1]=='s') or
               (cmd.len == 5 and cmd[0]=='p' and cmd[1]=='r' and cmd[2]=='o' and cmd[3]=='g' and cmd[4]=='s')) {
        const mods = mb.module_slice();
        if (mods.len == 0) {
            logger.write_raw("No programs found.\r\n");
        } else {
            logger.write_raw("Programs:\r\n");
            var mi: usize = 0;
            while (mi < mods.len) : (mi += 1) {
                const name = mb.module_name(mods[mi]);
                logger.write_raw(" - ");
                logger.write_raw(name);
                logger.write_raw("\r\n");
            }
        }
    } else if (cmd.len == 3 and cmd[0]=='r' and cmd[1]=='u' and cmd[2]=='n') {
        const mods = mb.module_slice();
        if (args.len == 0) {
            logger.write_raw("Usage: run <program>\r\n");
            return;
        }
        var found = false;
        var mi: usize = 0;
        while (mi < mods.len) : (mi += 1) {
            const name = mb.module_name(mods[mi]);
            if (name.len == args.len) {
                var eq = true;
                var k: usize = 0;
                while (k < args.len) : (k += 1) {
                    if (name[k] != args[k]) { eq = false; break; }
                }
                if (eq) {
                    found = true;
                    const img_ptr: usize = mods[mi].mod_start;
                    const img_len: usize = mods[mi].mod_end - mods[mi].mod_start;
                    if (elf.load_from_memory(img_ptr, img_len)) |entry| {
                        // Map user stack and jump to user mode; this call never returns
                        paging.map_page(user.USER_STACK_TOP - 0x1000, user.USER_STACK_TOP - 0x1000, true, true);
                        flush_tlb();
                        logger.write_raw("Launching "); logger.write_raw(name); logger.write_raw("...\r\n");
                        enter_user_mode(@as(u32, @truncate(entry)), @intCast(user.USER_STACK_TOP), gdt.USER_DS, gdt.USER_CS);
                        unreachable;
                    } else {
                        logger.write_raw("ELF load failed for "); logger.write_raw(name); logger.write_raw("\r\n");
                    }
                    break;
                }
            }
        }
        if (!found) {
            logger.write_raw("Program not found: "); logger.write_raw(args); logger.write_raw("\r\n");
        }
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
