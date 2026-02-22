const paging = @import("paging.zig");
const logger = @import("logger.zig");

pub const Elf32_Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u32,
    e_phoff: u32,
    e_shoff: u32,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

pub const Elf32_Phdr = extern struct {
    p_type: u32,
    p_offset: u32,
    p_vaddr: u32,
    p_paddr: u32,
    p_filesz: u32,
    p_memsz: u32,
    p_flags: u32,
    p_align: u32,
};

const PT_LOAD: u32 = 1;

fn memcpy(dst: [*]u8, src: [*]const u8, n: usize) void {
    var i: usize = 0; while (i < n) : (i += 1) dst[i] = src[i];
}

fn memset(dst: [*]u8, val: u8, n: usize) void {
    var i: usize = 0; while (i < n) : (i += 1) dst[i] = val;
}

pub fn load_from_memory(image_ptr: usize, image_len: usize) ?u32 {
    // Ensure the module memory is accessible to the kernel (identity-map its pages)
    const map_start = image_ptr & ~(@as(usize, 0xFFF));
    const map_end = (image_ptr + image_len + 0xFFF) & ~(@as(usize, 0xFFF));
    paging.map_identity_range(map_start, map_end, 0x003);
    if (image_len < @sizeOf(Elf32_Ehdr)) return null;
    const eh: *const Elf32_Ehdr = @ptrFromInt(image_ptr);
    if (eh.e_ident[0] != 0x7F or eh.e_ident[1] != 'E' or eh.e_ident[2] != 'L' or eh.e_ident[3] != 'F') return null;
    const phoff = eh.e_phoff;
    const phnum = eh.e_phnum;
    const phentsize = eh.e_phentsize;
    if (phentsize != @sizeOf(Elf32_Phdr)) return null;
    if (phoff + @as(usize, phnum) * phentsize > image_len) return null;
    // Load segments at the virtual addresses encoded in the ELF
    var i: usize = 0;
    while (i < phnum) : (i += 1) {
        const ph_ptr: usize = image_ptr + phoff + i * phentsize;
        const ph: Elf32_Phdr = (@as(*const Elf32_Phdr, @ptrFromInt(ph_ptr))).*; // copy header locally
        if (ph.p_type != PT_LOAD) continue;
        const vaddr: usize = ph.p_vaddr;
        const memsz: usize = ph.p_memsz;
        const filesz: usize = ph.p_filesz;
        const off = ph.p_offset;
        if (off > image_len or filesz > image_len - off) return null;
        if (memsz < filesz) return null;
        // Map pages for this segment as user; writable if flags says so
        const writable = (ph.p_flags & 0x2) != 0; // PF_W
        var off_page: usize = 0;
        while (off_page < (memsz + 0xFFF) & ~@as(usize,0xFFF)) : (off_page += 0x1000) {
            // Back user virtual pages with fresh physical frames (avoid clobbering low memory / MBI)
            const phys = paging.alloc_phys_page();
            paging.map_page(vaddr + off_page, phys, true, writable);
        }
        // Copy file segment
        if (filesz > 0) {
            const dst: [*]u8 = @ptrFromInt(vaddr);
            const src: [*]const u8 = @ptrFromInt(image_ptr + off);
            // Bounce buffer to avoid overlap issues if source and destination alias
            var bounce: [4096]u8 = undefined;
            var copied: usize = 0;
            while (copied < filesz) : (copied += @min(bounce.len, filesz - copied)) {
                const chunk = @min(bounce.len, filesz - copied);
                memcpy(&bounce, src + copied, chunk);
                memcpy(dst + copied, &bounce, chunk);
            }
        }
        // Zero BSS (memsz - filesz)
        if (memsz > filesz) {
            const bss_start: [*]u8 = @ptrFromInt(vaddr + filesz);
            memset(bss_start, 0, memsz - filesz);
        }
    }
    return eh.e_entry;
}
