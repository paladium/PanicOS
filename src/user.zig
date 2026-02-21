const paging = @import("paging.zig");
const gdt = @import("gdt.zig");

extern fn enter_user_mode(entry: u32, user_stack: u32, user_ds: u16, user_cs: u16) callconv(.C) void;
extern fn flush_tlb() callconv(.C) void;
const logger = @import("logger.zig");

// Place a tiny flat binary: mov eax,1 ; mov ebx,msg ; mov ecx,len ; int 0x80 ; jmp .
// For now, no syscalls path; instead write to VGA directly.

pub const USER_BASE: usize = 0x0040_0000; // 4 MiB
pub const USER_STACK_TOP: usize = 0x0080_0000; // 8 MiB

pub fn map_and_enter() noreturn {
    // Map one page for code and one for stack as user
    const code_phys = USER_BASE;
    const stack_phys = USER_STACK_TOP - 0x1000;
    paging.map_page(USER_BASE, code_phys, true, true);
    paging.map_page(USER_STACK_TOP - 0x1000, stack_phys, true, true);
    // Map VGA text buffer for user so it can write
    paging.map_page(0xB8000, 0xB8000, true, true);

    // Prepare a tiny user program that uses int 0x80 write/exit
    var code: [*]u8 = @ptrFromInt(code_phys);
    var i: usize = 0;
    const msg = "User via syscall!\r\n";
    const msg_addr: u32 = @intCast(USER_BASE + 128);
    const msg_len: u32 = msg.len;
    // Assemble:
    // mov eax,1; mov ebx,1; mov ecx,msg_addr; mov edx,msg_len; int 0x80
    // mov eax,2; mov ebx,0; int 0x80; jmp $
    inline for ([_]u8{
        0xB8, 0x01,0x00,0x00,0x00,            // mov eax,1 (SYS_write)
        0xBB, 0x01,0x00,0x00,0x00,            // mov ebx,1 (fd)
        0xB9, @as(u8,@truncate(msg_addr)), @as(u8,@truncate(msg_addr>>8)), @as(u8,@truncate(msg_addr>>16)), @as(u8,@truncate(msg_addr>>24)), // mov ecx,imm32
        0xBA, @as(u8,@truncate(msg_len)), @as(u8,@truncate(msg_len>>8)), @as(u8,@truncate(msg_len>>16)), @as(u8,@truncate(msg_len>>24)),     // mov edx,imm32
        0xCD, 0x80,                            // int 0x80
        0xB8, 0x02,0x00,0x00,0x00,            // mov eax,2 (SYS_exit)
        0xBB, 0x00,0x00,0x00,0x00,            // mov ebx,0
        0xCD, 0x80,                            // int 0x80
        0xEB, 0xFE,                            // jmp $
    }) |b| { code[i] = b; i += 1; }
    // Place message at USER_BASE+128
    var msg_ptr: [*]u8 = @ptrFromInt(USER_BASE + 128);
    var j: usize = 0; while (j < msg.len) : (j += 1) msg_ptr[j] = msg[j];

    // Flush TLB so user mappings (and PDE user bit changes) take effect
    flush_tlb();
    // Log the frame we are about to iret to
    const eip: u32 = @intCast(USER_BASE);
    const esp: u32 = @intCast(USER_STACK_TOP);
    const ucs: u32 = gdt.USER_CS;
    const uds: u32 = gdt.USER_DS;
    logger.log_hex("IRET.EIP", @as([*]const u8, @ptrCast(&eip))[0..@sizeOf(u32)]);
    logger.log_hex("IRET.CS ", @as([*]const u8, @ptrCast(&ucs))[0..@sizeOf(u32)]);
    logger.log_hex("IRET.ESP", @as([*]const u8, @ptrCast(&esp))[0..@sizeOf(u32)]);
    logger.log_hex("IRET.SS ", @as([*]const u8, @ptrCast(&uds))[0..@sizeOf(u32)]);
    // Enter ring3 at USER_BASE with user stack
    enter_user_mode(@as(u32, @truncate(USER_BASE)), @as(u32, @truncate(USER_STACK_TOP)), gdt.USER_DS, gdt.USER_CS);
    unreachable;
}
