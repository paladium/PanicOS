const logger = @import("logger.zig");

extern fn outb(port: u16, value: u8) callconv(.C) void;
extern fn inb(port: u16) callconv(.C) u8;
extern fn read_cr2() callconv(.C) u32;
extern fn read_cr0() callconv(.C) u32;
extern fn read_cr3() callconv(.C) u32;
extern fn read_cr4() callconv(.C) u32;
extern fn read_ss() callconv(.C) u32;
extern fn read_ds() callconv(.C) u32;
extern fn enable_interrupts() callconv(.C) void;
extern fn cpu_halt() callconv(.C) void;

// PIC ports
const PIC1: u16 = 0x20;
const PIC2: u16 = 0xA0;
const PIC1_COMMAND: u16 = PIC1;
const PIC1_DATA: u16 = PIC1 + 1;
const PIC2_COMMAND: u16 = PIC2;
const PIC2_DATA: u16 = PIC2 + 1;
const PIC_EOI: u8 = 0x20;

fn exc_name(vec: u32) []const u8 {
    return switch (vec) {
        0 => "#DE Divide Error",
        1 => "#DB Debug",
        2 => "NMI",
        3 => "#BP Breakpoint",
        4 => "#OF Overflow",
        5 => "#BR BOUND",
        6 => "#UD Invalid Opcode",
        7 => "#NM Device Not Available",
        8 => "#DF Double Fault",
        9 => "Coprocessor Segment Overrun",
        10 => "#TS Invalid TSS",
        11 => "#NP Segment Not Present",
        12 => "#SS Stack-Segment Fault",
        13 => "#GP General Protection",
        14 => "#PF Page Fault",
        16 => "#MF x87 FP",
        17 => "#AC Alignment Check",
        18 => "#MC Machine Check",
        19 => "#XM SIMD FP",
        else => "Exception",
    };
}

const TrapRecord = extern struct {
    magic: u32,
    vec: u32,
    err: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
    uesp: u32,
    uss: u32,
    cr2: u32,
};

var last_exc: TrapRecord = .{ .magic = 0x45584350, .vec = 0, .err = 0, .eip = 0, .cs = 0, .eflags = 0, .uesp = 0, .uss = 0, .cr2 = 0 };
const REC_ADDR: usize = 0x0009_F000; // identity-mapped scratch area for host-side inspection

pub export fn isr_dispatch(vec: u32, err: u32, frame: [*]const u32, base_off: u32) callconv(.C) void {
    // Frame layout pointed by `frame`: [EIP, CS, EFLAGS, (ESP, SS if CPL change)]
    const off = base_off >> 2; // u32 slots
    const eip = frame[off + 0];
    const cs = frame[off + 1];
    const eflags = frame[off + 2];
    const from_user = (cs & 0x3) == 0x3;
    var uesp: u32 = 0;
    var uss: u32 = 0;
    if (from_user) {
        uesp = frame[off + 3];
        uss = frame[off + 4];
    }
    // Persist exception record (global + fixed phys addr)
    last_exc.vec = vec;
    last_exc.err = err;
    last_exc.eip = eip;
    last_exc.cs = cs;
    last_exc.eflags = eflags;
    last_exc.uesp = uesp;
    last_exc.uss = uss;
    last_exc.cr2 = if (vec == 14) read_cr2() else 0;
    const rec_ptr: *volatile TrapRecord = @ptrFromInt(REC_ADDR);
    rec_ptr.* = last_exc; // volatile store via pointer type
    logger.log_hex("VEC", @as([*]const u8, @ptrCast(&vec))[0..@sizeOf(u32)]);
    logger.log_hex("ERR", @as([*]const u8, @ptrCast(&err))[0..@sizeOf(u32)]);
    logger.log_hex("EIP", @as([*]const u8, @ptrCast(&eip))[0..@sizeOf(u32)]);
    logger.log_hex("CS ", @as([*]const u8, @ptrCast(&cs))[0..@sizeOf(u32)]);
    logger.log_hex("EFL", @as([*]const u8, @ptrCast(&eflags))[0..@sizeOf(u32)]);
    if (from_user) {
        logger.log_hex("UESP", @as([*]const u8, @ptrCast(&uesp))[0..@sizeOf(u32)]);
        logger.log_hex("USS ", @as([*]const u8, @ptrCast(&uss))[0..@sizeOf(u32)]);
    }
    // Always log SS/DS and CRs for deeper diagnostics
    const ss_now = read_ss();
    const ds_now = read_ds();
    const cr0 = read_cr0();
    const cr3 = read_cr3();
    const cr4 = read_cr4();
    logger.log_hex("SS ", @as([*]const u8, @ptrCast(&ss_now))[0..@sizeOf(u32)]);
    logger.log_hex("DS ", @as([*]const u8, @ptrCast(&ds_now))[0..@sizeOf(u32)]);
    logger.log_hex("CR0", @as([*]const u8, @ptrCast(&cr0))[0..@sizeOf(u32)]);
    logger.log_hex("CR3", @as([*]const u8, @ptrCast(&cr3))[0..@sizeOf(u32)]);
    logger.log_hex("CR4", @as([*]const u8, @ptrCast(&cr4))[0..@sizeOf(u32)]);
    if (vec == 6) { // #UD Invalid Opcode
        logger.log(.err, "#UD details");
        // Dump 16 bytes at EIP (may fault if unmapped, but usually valid)
        const ptr: [*]const u8 = @ptrFromInt(eip);
        logger.log_hex("UD.EIP+0", ptr[0..@min(@as(usize,16), @as(usize,16))]);
        // Also dump previous 8 bytes if accessible
        if (eip >= 8) {
            const p2: [*]const u8 = @ptrFromInt(eip - 8);
            logger.log_hex("UD.EIP-8", p2[0..16]);
        }
    } else if (vec == 14) {
        const cr2 = read_cr2();
        // Decode error code bits: P=bit0, W/R=bit1, U/S=bit2, RSVD=bit3, I/D=bit4
        const p: u8 = if ((err & 1) != 0) @as(u8, '1') else @as(u8, '0');
        const wr: u8 = if ((err & 2) != 0) @as(u8, 'W') else @as(u8, 'R');
        const us: u8 = if ((err & 4) != 0) @as(u8, 'U') else @as(u8, 'S');
        logger.log(.err, "#PF details");
        var buf: [4]u8 = .{ @intCast(p), @intCast(wr), @intCast(us), 0 };
        logger.log_hex("CR2", @as([*]const u8, @ptrCast(&cr2))[0..@sizeOf(u32)]);
        logger.log_hex("ERR", @as([*]const u8, @ptrCast(&err))[0..@sizeOf(u32)]);
        logger.log_hex("Ebits", buf[0..3]);
    } else {
        if (vec == 13) { // #GP decode
            const sel: u32 = err & 0xFFFF;
            const ext: u8 = @intCast(err & 1);
            const idt: u8 = @intCast((err >> 1) & 1);
            const ti: u8 = @intCast((err >> 2) & 1);
            const index: u32 = (err >> 3) & 0x1FFF;
            logger.log(.err, "#GP details");
            logger.log_hex("SEL", @as([*]const u8, @ptrCast(&sel))[0..@sizeOf(u32)]);
            logger.log_hex("IDX", @as([*]const u8, @ptrCast(&index))[0..@sizeOf(u32)]);
            var bits: [4]u8 = .{ if (ext!=0) 'E' else '-', if (idt!=0) 'I' else 'G', if (ti!=0) 'L' else 'G', 0 };
            logger.log_hex("FLG", bits[0..3]);
        }
        logger.log(.err, exc_name(vec));
    }
    logger.log(.err, "CPU exception; halting");
    while (true) {}
}

// Syscall ABI (Linux-like subset):
// EAX = num; EBX = fd; ECX = buf; EDX = len
// Returns in EAX.
const SYS = struct {
    pub const write: u32 = 1;
    pub const exit: u32 = 2;
    pub const yield: u32 = 3;
};

// Simple, unambiguous syscall ABI for ISR: pass EAX,EBX,ECX,EDX; return value in EAX.
pub export fn syscall_dispatch_abi(eax: u32, ebx: u32, ecx: u32, edx: u32) callconv(.C) u32 {
    switch (eax) {
        SYS.write => {
            const buf_ptr = ecx;
            const len = edx;
            if (len != 0 and buf_ptr != 0) {
                const buf: [*]const u8 = @ptrFromInt(buf_ptr);
                const slice = buf[0..@intCast(len)];
                logger.write_raw(slice);
                return len;
            }
            return 0;
        },
        SYS.exit => {
            const code = ebx;
            _ = code;
            logger.log(.info, "user exit");
            // Idle the CPU in kernel so the system stays alive
            enable_interrupts();
            while (true) cpu_halt();
        },
        SYS.yield => {
            // Cooperative yield: simply return for now; a scheduler could switch tasks here
            return 0;
        },
        else => {
            logger.log(.warn, "unknown syscall");
            return 0xFFFF_FFFF; // -ENOSYS
        },
    }
}

pub export fn irq0_handler() callconv(.C) void {
    on_timer();
    outb(PIC1_COMMAND, PIC_EOI);
}

pub export fn irq1_handler() callconv(.C) void {
    outb(0xE9, 'K');
    on_keyboard();
    outb(PIC1_COMMAND, PIC_EOI);
}

fn on_timer() void {}

fn on_keyboard() void {
    const scancode = inb(0x60);
    var buf: [1]u8 = .{scancode};
    logger.log_hex("KBD", buf[0..]);
}

pub fn pic_remap() void {
    // Remap PIC to 0x20 and 0x28
    const ICW1: u8 = 0x11; // edge triggered, cascaded, ICW4
    const ICW4: u8 = 0x01; // 8086 mode
    // save masks
    _ = inb(PIC1_DATA);
    _ = inb(PIC2_DATA);
    outb(PIC1_COMMAND, ICW1);
    outb(PIC2_COMMAND, ICW1);
    outb(PIC1_DATA, 0x20);
    outb(PIC2_DATA, 0x28);
    outb(PIC1_DATA, 4);
    outb(PIC2_DATA, 2);
    outb(PIC1_DATA, ICW4);
    outb(PIC2_DATA, ICW4);
    // Explicitly unmask only IRQ0 (timer) and IRQ1 (keyboard) on master; mask all on slave
    outb(PIC1_DATA, 0xFC);
    outb(PIC2_DATA, 0xFF);
}

pub fn pit_init(hz: u32) void {
    const PIT_CMD: u16 = 0x43;
    const PIT_CH0: u16 = 0x40;
    const base: u32 = 1193180;
    var divisor: u32 = if (hz == 0) 0 else base / hz;
    if (divisor == 0 or divisor > 0xFFFF) divisor = 0xFFFF;
    outb(PIT_CMD, 0x36); // channel 0, lobyte/hibyte, mode 3, binary
    outb(PIT_CH0, @intCast(divisor & 0xFF));
    outb(PIT_CH0, @intCast((divisor >> 8) & 0xFF));
}

// Minimal PS/2 controller init to ensure keyboard IRQs are enabled
fn ps2_wait_input_clear() void { // wait until input buffer clear
    var i: usize = 0;
    while (i < 100000) : (i += 1) {
        if ((inb(0x64) & 0x02) == 0) break;
    }
}

fn ps2_wait_output_full() bool { // wait until output buffer full
    var i: usize = 0;
    while (i < 100000) : (i += 1) {
        if ((inb(0x64) & 0x01) != 0) return true;
    }
    return false;
}

fn ps2_flush_output() void {
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        if ((inb(0x64) & 0x01) != 0) {
            _ = inb(0x60);
        } else break;
    }
}

pub fn keyboard_enable() void {
    ps2_flush_output();
    // Read command byte
    ps2_wait_input_clear();
    outb(0x64, 0x20);
    if (ps2_wait_output_full()) {
        var cmd: u8 = inb(0x60);
        cmd |= 0x01; // enable IRQ1
        // Write command byte
        ps2_wait_input_clear();
        outb(0x64, 0x60);
        ps2_wait_input_clear();
        outb(0x60, cmd);
    }
    // Enable first PS/2 port
    ps2_wait_input_clear();
    outb(0x64, 0xAE);
    // Enable keyboard scanning on the device (0xF4)
    ps2_wait_input_clear();
    outb(0x60, 0xF4);
    // Optional: read ACK if present
    if (ps2_wait_output_full()) { _ = inb(0x60); }
}
