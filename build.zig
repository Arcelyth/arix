const std = @import("std");
const Generator = @import("src/build/Generator.zig");

const test_targets = [_]std.Target.Query{
    .{}, // native
};

const AnonItem = struct {
    name: []const u8,
    path: std.Build.LazyPath,
};

const DependItem = struct {
    name: []const u8,
    dep: *std.Build.Dependency,
    module: []const u8,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    var anon_imports: std.ArrayList(AnonItem) = .empty;
    var depends: std.ArrayList(DependItem) = .empty;

    const test_step = b.step("test", "Run all tests");

    // config
    const debug = b.option(bool, "debug", "show debug information") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "debug", debug);

    // dependencies
    const strale = b.dependency("strale", .{
        .target = target,
        .optimize = optimize,
    });
    try depends.append(b.allocator, .{ .name = "strale", .dep = strale, .module = "strale" });

    // generate
    const named_ref = Generator.generate(b, "gen_named_ref", "./src/gen/named_ref.zig", &.{"./res/json/named_char_refs.json"}, "gen_named_ref.zig");
    const local_name = Generator.generate(b, "gen_local_name", "./src/gen/local_name.zig", &.{"./res/json/local_names.json"}, "gen_local_name.zig");
    try anon_imports.append(b.allocator, .{ .name = "named_ref", .path = named_ref });
    try anon_imports.append(b.allocator, .{ .name = "local_name", .path = local_name });

    // executable
    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    moduleAddCommon(exe_module, anon_imports, depends, options);

    const exe = b.addExecutable(.{ .name = "main", .root_module = exe_module });

    // test
    for (test_targets) |t| {
        const test_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(t),
        });

        moduleAddCommon(test_module, anon_imports, depends, options);
        const unit_tests = b.addTest(.{ .name = "tests", .root_module = test_module });

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    b.installArtifact(exe);
}

fn moduleAddCommon(
    m: *std.Build.Module,
    anon_imports: std.ArrayList(AnonItem),
    depends: std.ArrayList(DependItem),
    options: *std.Build.Step.Options,
) void {
    for (anon_imports.items) |an| {
        m.addAnonymousImport(an.name, .{
            .root_source_file = an.path,
        });
    }
    for (depends.items) |depend| {
        m.addImport(depend.name, depend.dep.module(depend.module));
    }
    m.addOptions("config", options);
}
