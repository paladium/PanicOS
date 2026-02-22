const PAGES = 4096;
const PAGE_SIZE: usize = 4096;

pub const PageDir = extern struct { entries: [1024]u32 };
pub const PageTab = extern struct { entries: [1024]u32 };

fn align_up(x: usize, a: usize) usize { return (x + a - 1) & ~(a - 1); }

var page_directory: PageDir align(4096) = .{ .entries = [_]u32{0} ** 1024 };
var pt0: PageTab align(4096) = .{ .entries = [_]u32{0} ** 1024 }; // 0..4MiB
var pt1: PageTab align(4096) = .{ .entries = [_]u32{0} ** 1024 }; // 4..8MiB
var pt2: PageTab align(4096) = .{ .entries = [_]u32{0} ** 1024 }; // 8..12MiB (for stack)
var pt_extra: [16]PageTab align(4096) = [_]PageTab{.{ .entries = [_]u32{0} ** 1024 }} ** 16; // extra tables for higher addrs
var extra_used: usize = 0;
var phys_bump: usize = 16 * 1024 * 1024; // simple physical page bump allocator starting at 16MiB

extern fn set_cr3(pdir: u32) callconv(.C) void;
extern fn enable_paging() callconv(.C) void;
extern fn flush_tlb() callconv(.C) void;

inline fn pde(addr: usize) usize { return (addr >> 22) & 0x3FF; }
inline fn pte(addr: usize) usize { return (addr >> 12) & 0x3FF; }

fn get_tab_for_dir(dir: usize) *PageTab {
    if (dir == 0) {
        if (page_directory.entries[0] == 0) page_directory.entries[0] = (@as(u32, @truncate(@intFromPtr(&pt0))) & 0xFFFFF000) | 0x003;
        return &pt0;
    } else if (dir == 1) {
        if (page_directory.entries[1] == 0) page_directory.entries[1] = (@as(u32, @truncate(@intFromPtr(&pt1))) & 0xFFFFF000) | 0x003;
        return &pt1;
    } else if (dir == 2) {
        if (page_directory.entries[2] == 0) page_directory.entries[2] = (@as(u32, @truncate(@intFromPtr(&pt2))) & 0xFFFFF000) | 0x003;
        return &pt2;
    } else {
        if (page_directory.entries[dir] == 0) {
            if (extra_used >= pt_extra.len) return &pt0; // fallback, out of tables
            const tab: *PageTab = &pt_extra[extra_used];
            extra_used += 1;
            page_directory.entries[dir] = (@as(u32, @truncate(@intFromPtr(tab))) & 0xFFFFF000) | 0x003;
            return tab;
        } else {
            const addr = page_directory.entries[dir] & 0xFFFFF000;
            return @ptrFromInt(@as(usize, addr));
        }
    }
}

pub fn map_identity_range(start: usize, end: usize, flags: u32) void {
    var addr = start & ~(@as(usize, PAGE_SIZE - 1));
    while (addr < end) : (addr += PAGE_SIZE) {
        const dir = pde(addr);
        const tab_idx = pte(addr);
        var tab: *PageTab = get_tab_for_dir(dir);
        tab.entries[tab_idx] = (@as(u32, @truncate(addr)) & 0xFFFFF000) | flags;
    }
}

pub fn map_page(vaddr: usize, paddr: usize, user: bool, writable: bool) void {
    const dir = pde(vaddr);
    const tab_idx = pte(vaddr);
    var tab: *PageTab = get_tab_for_dir(dir);
    // Ensure PDE has user bit if mapping user pages under it
    if (user) page_directory.entries[dir] |= 0x004;
    var flags: u32 = 0x001; // present
    if (writable) flags |= 0x002;
    if (user) flags |= 0x004;
    tab.entries[tab_idx] = (@as(u32, @truncate(paddr)) & 0xFFFFF000) | flags;
}

pub fn alloc_phys_page() usize {
    const addr = phys_bump & ~(@as(usize, PAGE_SIZE - 1));
    phys_bump = addr + PAGE_SIZE;
    return addr;
}

pub fn enable() void {
    // Identity map first 12MiB (0..12MiB)
    map_identity_range(0, 12 * 1024 * 1024, 0x003);
    set_cr3(@as(u32, @truncate(@intFromPtr(&page_directory))));
    enable_paging();
}

// Remove all user-accessible mappings (PTEs with U/S bit set) across the page tables
// and clear the PDE user bit. Keeps kernel supervisor mappings intact.
pub fn clear_user_mappings() void {
    var dir: usize = 0;
    while (dir < 1024) : (dir += 1) {
        const pde_val = page_directory.entries[dir];
        if (pde_val == 0) continue;
        // Obtain the page table pointer from PDE value
        const tab_addr = pde_val & 0xFFFFF000;
        var tab: *PageTab = @ptrFromInt(@as(usize, tab_addr));
        var any_user: bool = false;
        var i: usize = 0;
        while (i < 1024) : (i += 1) {
            const pte_val = tab.entries[i];
            if ((pte_val & 0x004) != 0) { // user bit set
                any_user = true;
                // Compute virtual address of this PTE
                const vaddr: usize = (dir << 22) | (i << 12);
                const paddr: usize = @intCast(pte_val & 0xFFFFF000);
                // If this falls within the kernel's identity-mapped window (0..12MiB)
                // and points to the same physical frame, downgrade to supervisor mapping
                if (vaddr < 12 * 1024 * 1024 and paddr == (vaddr & 0xFFFFF000)) {
                    tab.entries[i] = (@as(u32, @truncate(vaddr)) & 0xFFFFF000) | 0x003; // present|rw, supervisor
                } else {
                    tab.entries[i] = 0; // fully unmap non-identity user pages
                }
            }
        }
        if (any_user) {
            // Ensure PDE user bit cleared; keep present/writable as-is
            page_directory.entries[dir] = pde_val & ~@as(u32, 0x004);
        }
    }
    // Restore kernel identity map for low memory to ensure Multiboot and other
    // low-phys structures remain accessible to the kernel.
    map_identity_range(0, 12 * 1024 * 1024, 0x003);
    // Flush after bulk changes
    flush_tlb();
}
