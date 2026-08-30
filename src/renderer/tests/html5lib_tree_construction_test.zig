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
const Node = @import("../dom/Node.zig");
const Element = @import("../dom/Element.zig");
const Text = @import("../dom/Text.zig");
const Comment = @import("../dom/Comment.zig");
const DocumentType = @import("../dom/DocumentType.zig");
const Attr = @import("../dom/Attr.zig");
const Namespace = @import("../dom/namespace.zig").Namespace;

const testing = std.testing;

const FragmentContext = struct {
    namespace: Namespace,
    local_name: []const u8,
};

fn parseFragmentContext(value: []const u8) FragmentContext {
    if (std.mem.indexOfScalar(u8, value, ' ')) |separator| {
        const prefix = value[0..separator];
        const namespace: Namespace = if (std.mem.eql(u8, prefix, "svg"))
            .NS_Svg
        else if (std.mem.eql(u8, prefix, "math"))
            .NS_Math
        else
            .NS_Html;
        return .{ .namespace = namespace, .local_name = value[separator + 1 ..] };
    }
    return .{ .namespace = .NS_Html, .local_name = value };
}

fn appendIndent(out: *std.ArrayList(u8), allocator: std.mem.Allocator, depth: usize) !void {
    try out.appendSlice(allocator, "| ");
    for (0..depth) |_| try out.appendSlice(allocator, "  ");
}

/// For sorting.
fn attrLessThan(_: void, lhs: Attr, rhs: Attr) bool {
    return std.mem.order(u8, lhs.local_name.slice(), rhs.local_name.slice()) == .lt;
}

/// Serialize a DOM node and its children into html5lib tree format.
fn serializeNode(out: *std.ArrayList(u8), allocator: std.mem.Allocator, node: *Node, depth: usize) !void {
    if (out.items.len != 0) try out.append(allocator, '\n');
    try appendIndent(out, allocator, depth);
    switch (node.type_id) {
        .DOM_Element => {
            const element = node.downcast(Element);
            const prefix: []const u8 = switch (element.ns orelse .NS_Html) {
                .NS_Math => "math ",
                .NS_Svg => "svg ",
                else => "",
            };
            try out.append(allocator, '<');
            try out.appendSlice(allocator, prefix);
            try out.appendSlice(allocator, element.local_name.slice());
            try out.append(allocator, '>');

            const attrs = try allocator.dupe(Attr, element.attrs.data.items);
            defer allocator.free(attrs);
            std.mem.sort(Attr, attrs, {}, attrLessThan);
            for (attrs) |attr| {
                try out.append(allocator, '\n');
                try appendIndent(out, allocator, depth + 1);

                const attr_prefix: []const u8 = switch (attr.ns orelse .NS_Html) {
                    .NS_XLink => "xlink ",
                    .NS_Xml => "xml ",
                    .NS_Xmlns => "xmlns ",
                    else => "",
                };
                try out.appendSlice(allocator, attr_prefix);
                try out.appendSlice(allocator, attr.local_name.slice());
                try out.appendSlice(allocator, "=\"");
                try out.appendSlice(allocator, attr.value.slice());
                try out.append(allocator, '"');
            }

            if (element.ns == .NS_Html and element.local_name.is(.template)) {
                if (element.temp_contents) |contents| {
                    try out.append(allocator, '\n');
                    try appendIndent(out, allocator, depth + 1);
                    try out.appendSlice(allocator, "content");
                    var content_child = contents.node.first_child;
                    while (content_child) |item| : (content_child = item.next_sibling)
                        try serializeNode(out, allocator, item, depth + 2);
                }
            }
        },
        .DOM_Text => {
            try out.append(allocator, '"');
            try out.appendSlice(allocator, node.downcast(Text).data.slice());
            try out.append(allocator, '"');
        },
        .DOM_Comment => {
            try out.appendSlice(allocator, "<!-- ");
            try out.appendSlice(allocator, node.downcast(Comment).data.slice());
            try out.appendSlice(allocator, " -->");
        },
        .DOM_DocumentType => {
            const doctype = node.downcast(DocumentType);
            try out.appendSlice(allocator, "<!DOCTYPE ");
            try out.appendSlice(allocator, doctype.name.slice());
            // Serialize public and system identifiers when present.
            if (!doctype.public_id.isEmpty() or !doctype.system_id.isEmpty()) {
                try out.appendSlice(allocator, " \"");
                try out.appendSlice(allocator, doctype.public_id.slice());
                try out.appendSlice(allocator, "\" \"");
                try out.appendSlice(allocator, doctype.system_id.slice());
                try out.append(allocator, '"');
            }
            try out.append(allocator, '>');
        },
        else => return,
    }

    var child = node.first_child;
    while (child) |item| : (child = item.next_sibling)
        try serializeNode(out, allocator, item, depth + 1);
}

fn serializeDocument(allocator: std.mem.Allocator, document: *Node) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var child = document.first_child;
    while (child) |item| : (child = item.next_sibling)
        try serializeNode(&out, allocator, item, 0);
    return try out.toOwnedSlice(allocator);
}

/// A single html5lib tree construction test case.
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
        strale.setGlobalAlloc(allocator);
        // Initialize tree builder and adapters.
        var test_tr_adapter = TestTreeAdapter.init(allocator);
        defer test_tr_adapter.deinit();

        const tree_adapter = test_tr_adapter.adapter();
        var tree_builder = TreeBuilder.init(allocator, tree_adapter, case.fragment != null);
        defer tree_builder.deinit();

        var fragment_context: ?*Element = null;
        defer if (fragment_context) |context| context.asNode().destroy(allocator);
        var fragment_root: ?*Element = null;
        if (case.fragment) |context_name| {
            const parsed_context = parseFragmentContext(context_name);
            const context = Element.create(
                tree_builder.document,
                try LocalName.fromSlice(parsed_context.local_name),
                parsed_context.namespace,
                null,
                null,
                false,
                null,
            );

            fragment_context = context;
            tree_builder.context = context;
            tree_builder.scripting_mode = .Fragment;

            const root = Element.create(
                tree_builder.document,
                LocalName.fromTag(.html),
                .NS_Html,
                null,
                null,
                false,
                null,
            );
            fragment_root = root;
            tree_builder.document.asNode().appendChild(root.asNode());
            try tree_builder.open_elements.append(root);
            // Fragment parsing starts in "in body" insertion mode.
            tree_builder.insert_mode = .InBodyMode;
        }

        const token_adapter = tree_builder.adapter();
        var tokenizer = Tokenizer.init(allocator, token_adapter, .{});
        defer tokenizer.deinit();

        var buffer = try BufferDeque(.utf8, .not_atomic, true).init(allocator);
        defer buffer.deinit();

        const data = case.data;
        if (config.debug) std.debug.print("tree case: {s}\n", .{data});
        try buffer.pushBackSlice(data);
        if (config.debug)
            std.debug.print("==========\n {s} \n", .{data});

        try tokenizer.step_E(&buffer);

        const serialization_root = if (fragment_root) |root| root.asNode() else tree_builder.document.asNode();
        const actual = try serializeDocument(allocator, serialization_root);
        defer allocator.free(actual);
        testing.expectEqualStrings(case.expected, actual) catch |err| {
            std.debug.print("\ninput: {s}\n", .{case.data});
            return err;
        };
    }
}

test "html5lib tree_construction adoption01" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/adoption01.dat", testing.io);
}

test "html5lib tree_construction adoption02" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/adoption02.dat", testing.io);
}

test "html5lib tree_construction blocks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/blocks.dat", testing.io);
}

test "html5lib tree_construction comments01" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/comments01.dat", testing.io);
}

test "html5lib tree_construction doctype01" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/doctype01.dat", testing.io);
}

test "html5lib tree_construction domjs-unsafe" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/domjs-unsafe.dat", testing.io);
}

test "html5lib tree_construction entities01" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/entities01.dat", testing.io);
}

test "html5lib tree_construction entities02" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/entities02.dat", testing.io);
}

test "html5lib tree_construction foreign-fragment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/foreign-fragment.dat", testing.io);
}

test "html5lib tree_construction html5test-com" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/html5test-com.dat", testing.io);
}

test "html5lib tree_construction inbody01" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/inbody01.dat", testing.io);
}

test "html5lib tree_construction isindex" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/isindex.dat", testing.io);
}

test "html5lib tree_construction main-element" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/main-element.dat", testing.io);
}

test "html5lib tree_construction math" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/math.dat", testing.io);
}

test "html5lib tree_construction menuitem-element" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/menuitem-element.dat", testing.io);
}

test "html5lib tree_construction namespace-sensitivity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/namespace-sensitivity.dat", testing.io);
}

//test "html5lib tree_construction noscript01" {
//    var arena = std.heap.ArenaAllocator.init(testing.allocator);
//    defer arena.deinit();
//    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/noscript01.dat", testing.io);
//}

//test "html5lib tree_construction pending-spec-changes-plain-text-unsafe" {
//    var arena = std.heap.ArenaAllocator.init(testing.allocator);
//    defer arena.deinit();
//    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/pending-spec-changes-plain-text-unsafe.dat", testing.io);
//}

//test "html5lib tree_construction pending-spec-changes" {
//    var arena = std.heap.ArenaAllocator.init(testing.allocator);
//    defer arena.deinit();
//    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/pending-spec-changes.dat", testing.io);
//}

test "html5lib tree_construction quirks01" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/quirks01.dat", testing.io);
}

// test "html5lib tree_construction plain-text-unsafe" {
//     var arena = std.heap.ArenaAllocator.init(testing.allocator);
//     defer arena.deinit();
//     try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/plain-text-unsafe.dat", testing.io);
// }

test "html5lib tree_construction ruby" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/ruby.dat", testing.io);
}

//test "html5lib tree_construction scriptdata01" {
//    var arena = std.heap.ArenaAllocator.init(testing.allocator);
//    defer arena.deinit();
//    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/scriptdata01.dat", testing.io);
//}

test "html5lib tree_construction search-element" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/search-element.dat", testing.io);
}

test "html5lib tree_construction svg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/svg.dat", testing.io);
}

test "html5lib tree_construction tables01" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/tables01.dat", testing.io);
}

test "html5lib tree_construction template" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/template.dat", testing.io);
}

test "html5lib tree_construction tests1" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try runHtml5LibTestFile(arena.allocator(), "src/renderer/tests/html5lib-tests/tree-construction/tests1.dat", testing.io);
}
