const std = @import("std");

const test_targets = [_]std.Target.Query{
    .{}, // native
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run all tests");

    // config
    const debug = b.option(bool, "debug", "show debug information") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "debug", debug);

    // executable
    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const strale = b.dependency("strale", .{
        .target = target,
        .optimize = optimize,
    });
    exe_module.addImport("strale", strale.module("strale"));
    exe_module.addOptions("config", options);

    const exe = b.addExecutable(.{ .name = "main", .root_module = exe_module });

    // test
    for (test_targets) |t| {
        const test_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(t),
        });
        test_module.addImport("strale", strale.module("strale"));
        test_module.addOptions("config", options);

        const unit_tests = b.addTest(.{ .name = "tests", .root_module = test_module });

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    b.installArtifact(exe);
}
