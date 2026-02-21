const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{ .cpu_arch = .x86, .os_tag = .freestanding, .abi = .none },
    });
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Strip symbols from the kernel") orelse false;

    const exe = b.addExecutable(.{
        .name = "panicos",
        .root_source_file = b.path("src/kernel.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.setLinkerScript(b.path("linker.ld"));
    exe.root_module.strip = strip;
    exe.addAssemblyFile(b.path("src/boot.S"));
    exe.addAssemblyFile(b.path("src/io.S"));
    exe.addAssemblyFile(b.path("src/interrupts.S"));
    // No PIE/strip in bare-metal build; keep defaults.

    b.installArtifact(exe);

    // Running is handled via scripts that build a GRUB ISO.
}
