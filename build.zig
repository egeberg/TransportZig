const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "aviation-transport-sim",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link raylib for 3D visualization (optional - comment out if not available)
    // exe.linkSystemLibrary("raylib");
    exe.linkLibC();

    // Note: Capy UI dependency can be added when available
    // For now, the UI module serves as a design reference
    // To add Capy: uncomment dependencies in build.zig.zon and the lines below
    // const capy_dep = b.dependency("capy", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // exe.root_module.addImport("capy", capy_dep.module("capy"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the aviation transport simulation");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
