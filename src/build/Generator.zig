/// Generator will use a Zig program in 'src/gen' folder to 
/// generate a Zig file and then exposes a module.
const Generator = @This();

const std = @import("std");
const DependItem = @import("DependItem.zig");

pub fn generate(
    b: *std.Build,
    name: []const u8,
    path: []const u8,
    files: []const []const u8,
    output: []const u8,
    depends: std.ArrayList(DependItem),
) *std.Build.Module{
    const gen_exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = b.graph.host,
        }),
    });

    const gen_step = b.addRunArtifact(gen_exe);
    for (files) |file| {
        gen_step.addFileArg(b.path(file));
    }
    const out_file = gen_step.addOutputFileArg(output);

    const gen_module = b.createModule(.{
        .root_source_file = out_file,
    });

    for (depends.items) |depend| {
        gen_module.addImport(depend.name, depend.dep.module(depend.module));
    }

    return gen_module;
}
