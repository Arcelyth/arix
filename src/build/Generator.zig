const Generator = @This();

const std = @import("std");

pub fn generate(
    b: *std.Build,
    name: []const u8,
    path: []const u8,
    files: []const  []const u8,
    output: []const u8,
) std.Build.LazyPath {
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
    return gen_step.addOutputFileArg(output);
}
