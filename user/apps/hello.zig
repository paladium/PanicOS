const sys = @import("sys");

pub export fn _start() callconv(.C) noreturn {
    const msg = "Hello from user via Zig!\r\n";
    _ = sys.write(1, msg);
    sys.exit(0);
}
