const std = @import("std");
const TestParser = @import("TestParser.zig");
const Tokenizer = @import("../html/tokenizer/Tokenizer.zig");
const TreeBuilder = @import("../html/tree_builder/TreeBuilder.zig");
const TokenAdapter = @import("../html/tokenizer/TokenAdapter.zig");
const TestTokenAdapter = @import("../html/tokenizer/TestAdapter.zig");
const TreeAdapter = @import("../html/tree_builder/TreeAdapter.zig");
const TestTreeAdapter = @import("../html/tree_builder/TestAdapter.zig");
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;
const BufferDeque = strale.BufferDeque;
const config = @import("config");
const LocalName = @import("local_name").LocalName;

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

    var tp = TestParser.init(content, allocator);
    var cases = try tp.parse();
    defer cases.deinit(tp.allocator);
    for (cases.items) |case| {
        var test_tr_adapter = TestTreeAdapter.init(allocator);
        defer test_tr_adapter.deinit();

        const tree_adapter = test_tr_adapter.adapter();
        var tree_builder = TreeBuilder.init(allocator, tree_adapter, false);

        const token_adapter = tree_builder.adapter();
        var tokenizer = Tokenizer.init(allocator, token_adapter, .{});
        defer tokenizer.deinit();

        strale.setGlobalAlloc(allocator);
        var buffer = try BufferDeque(.utf8, .not_atomic, true).init(allocator);
        defer buffer.deinit();

        const data = case.data;
        try buffer.pushBackSlice(data);
        if (config.debug) {
            std.debug.print("==========\n {s} \n", .{data});
        }
        try tokenizer.step_E(&buffer);
    }
}

test "html5lib tree_construction test1" {
    const alloc = testing.allocator;
    try runHtml5LibTestFile(alloc, "src/renderer/tests/html5lib-tests/tree-construction/tests1.dat", testing.io);
}
