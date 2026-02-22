pub const SYS_WRITE: u32 = 1;
pub const SYS_EXIT: u32 = 2;
pub const SYS_YIELD: u32 = 3;

pub inline fn write(fd: u32, buf: []const u8) u32 {
    const num: u32 = SYS_WRITE;
    const ptr: u32 = @intCast(@intFromPtr(buf.ptr));
    const len: u32 = @intCast(buf.len);
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32)
        : [num] "{eax}" (num), [a1] "{ebx}" (fd), [a2] "{ecx}" (ptr), [a3] "{edx}" (len)
        : "memory", "cc");
}

pub inline fn exit(code: u32) noreturn {
    const num: u32 = SYS_EXIT;
    asm volatile ("int $0x80"
        :
        : [num] "{eax}" (num), [a1] "{ebx}" (code)
        : "memory", "cc");
    unreachable;
}
