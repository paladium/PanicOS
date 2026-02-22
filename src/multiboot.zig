pub const Module = extern struct {
    mod_start: u32,
    mod_end: u32,
    string: u32,
    reserved: u32,
};

pub const Info = extern struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
    syms: [4]u32, // a.out or ELF
    mmap_length: u32,
    mmap_addr: u32,
    drives_length: u32,
    drives_addr: u32,
    config_table: u32,
    boot_loader_name: u32,
    apm_table: u32,
    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,
};

pub var g_mbi_ptr: usize = 0;

pub fn set_mbi(ptr: usize) void { g_mbi_ptr = ptr; }

pub fn module_slice() []const Module {
    if (g_mbi_ptr == 0) return &[_]Module{};
    const mbi: *const Info = @ptrFromInt(g_mbi_ptr);
    if ((mbi.flags & (1 << 3)) == 0 or mbi.mods_count == 0) return &[_]Module{};
    const mods: [*]const Module = @ptrFromInt(@as(usize, mbi.mods_addr));
    return mods[0..mbi.mods_count];
}

pub fn module_name(mod: Module) []const u8 {
    if (mod.string == 0) return &[_]u8{};
    const ptr: [*]const u8 = @ptrFromInt(@as(usize, mod.string));
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {}
    return ptr[0..len];
}
