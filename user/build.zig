const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_arch = .x86, .os_tag = .freestanding, .abi = .none } });
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Strip symbols from the user binaries") orelse false;

    // Scan user/apps/*.zig and build each as its own freestanding binary
    const gpa = std.heap.page_allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var apps_dir = std.fs.cwd().openDir("apps", .{ .iterate = true }) catch {
        // If apps dir missing, fall back to building the default app
        const exe = b.addExecutable(.{
            .name = "init",
            .root_source_file = b.path("apps/hello.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.entry = .{ .symbol_name = "_start" };
        exe.root_module.addAnonymousImport("sys", .{ .root_source_file = b.path("lib/sys.zig") });
        exe.root_module.strip = strip;
        b.installArtifact(exe);
        return;
    };
    defer apps_dir.close();
    var it = apps_dir.iterate();
    var found_any = false;
    while (it.next() catch null) |ent| {
        if (ent.kind != .file) continue;
        if (!std.mem.endsWith(u8, ent.name, ".zig")) continue;
        found_any = true;
        const stem = ent.name[0 .. ent.name.len - ".zig".len];
        const exe = b.addExecutable(.{
            .name = stem,
            .root_source_file = b.path(std.fmt.allocPrint(arena, "apps/{s}", .{ent.name}) catch ent.name),
            .target = target,
            .optimize = optimize,
        });
        exe.entry = .{ .symbol_name = "_start" };
        exe.root_module.addAnonymousImport("sys", .{ .root_source_file = b.path("lib/sys.zig") });
        exe.root_module.strip = strip;
        b.installArtifact(exe);
    }

    if (!found_any) {
        // Fallback: build the default hello app so the pipeline still works
        const exe = b.addExecutable(.{
            .name = "init",
            .root_source_file = b.path("apps/hello.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.entry = .{ .symbol_name = "_start" };
        exe.root_module.addAnonymousImport("sys", .{ .root_source_file = b.path("lib/sys.zig") });
        exe.root_module.strip = strip;
        b.installArtifact(exe);
    }
}
