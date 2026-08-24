const std = @import("std");
const TestParser = @import("TestParser.zig");

const testing = std.testing;

const TreeTest = struct {
    data: []const u8,
    expected: []const u8,

    errors: usize = 0,
    fragment: ?[]const u8 = null,
    scripting: ?bool = null,
};

fn runHtml5LibTestFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    io: std.Io,
) !void {
    const content = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .unlimited,
    );
    defer allocator.free(content);

    const tp = TestParser.init(content, testing.allocator);
    _ = tp;
}
