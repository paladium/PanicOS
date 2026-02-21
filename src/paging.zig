const PAGES = 4096;
const PAGE_SIZE: usize = 4096;

pub const PageDir = extern struct { entries: [1024]u32 };
pub const PageTab = extern struct { entries: [1024]u32 };

fn align_up(x: usize, a: usize) usize { return (x + a - 1) & ~(a - 1); }

var page_directory: PageDir align(4096) = .{ .entries = [_]u32{0} ** 1024 };
var pt0: PageTab align(4096) = .{ .entries = [_]u32{0} ** 1024 }; // 0..4MiB
var pt1: PageTab align(4096) = .{ .entries = [_]u32{0} ** 1024 }; // 4..8MiB
var pt2: PageTab align(4096) = .{ .entries = [_]u32{0} ** 1024 }; // 8..12MiB (for stack)

extern fn set_cr3(pdir: u32) callconv(.C) void;
extern fn enable_paging() callconv(.C) void;

inline fn pde(addr: usize) usize { return (addr >> 22) & 0x3FF; }
inline fn pte(addr: usize) usize { return (addr >> 12) & 0x3FF; }

pub fn map_identity_range(start: usize, end: usize, flags: u32) void {
    var addr = start & ~(@as(usize, PAGE_SIZE - 1));
    while (addr < end) : (addr += PAGE_SIZE) {
        const dir = pde(addr);
        const tab_idx = pte(addr);
        var tab: *PageTab = switch (dir) {
            0 => &pt0,
            1 => &pt1,
            2 => &pt2,
            else => &pt0, // minimal
        };
        if (page_directory.entries[dir] == 0) {
            page_directory.entries[dir] = (@as(u32, @truncate(@intFromPtr(tab))) & 0xFFFFF000) | 0x003; // present|rw
        }
        tab.entries[tab_idx] = (@as(u32, @truncate(addr)) & 0xFFFFF000) | flags;
    }
}

pub fn map_page(vaddr: usize, paddr: usize, user: bool, writable: bool) void {
    const dir = pde(vaddr);
    const tab_idx = pte(vaddr);
    var tab: *PageTab = switch (dir) {
        0 => &pt0,
        1 => &pt1,
        2 => &pt2,
        else => &pt0,
    };
    if (page_directory.entries[dir] == 0) {
        // Create PDE with present|rw and optionally user flag
        var pde_flags: u32 = 0x003;
        if (user) pde_flags |= 0x004;
        page_directory.entries[dir] = (@as(u32, @truncate(@intFromPtr(tab))) & 0xFFFFF000) | pde_flags;
    } else if (user) {
        // Ensure PDE has user bit if mapping user pages under it
        page_directory.entries[dir] |= 0x004;
    }
    var flags: u32 = 0x001; // present
    if (writable) flags |= 0x002;
    if (user) flags |= 0x004;
    tab.entries[tab_idx] = (@as(u32, @truncate(paddr)) & 0xFFFFF000) | flags;
}

pub fn enable() void {
    // Identity map first 12MiB (0..12MiB)
    map_identity_range(0, 12 * 1024 * 1024, 0x003);
    set_cr3(@as(u32, @truncate(@intFromPtr(&page_directory))));
    enable_paging();
}
