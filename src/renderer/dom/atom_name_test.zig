const std = @import("std");
const testing = std.testing;

const atom = @import("atom_name.zig");

test "static tag names" {
    const html = atom.AtomName.fromSlice("html");
    const div = atom.AtomName.fromSlice("div");

    try testing.expect(html == .static);
    try testing.expect(div == .static);

    try testing.expect(html.is(.html));
    try testing.expect(div.is(.div));
}

test "unknown names are dynamic" {
    const custom = atom.AtomName.fromSlice("custom-element");

    try testing.expect(custom == .dynamic);
    try testing.expectEqualStrings(
        "custom-element",
        custom.dynamic,
    );
}

test "static equality" {
    const a = atom.AtomName.fromSlice("body");
    const b = atom.AtomName.fromSlice("body");
    try testing.expect(a.eql(b));

    const c = atom.AtomName.fromSlice("div");
    const d = atom.AtomName.fromSlice("span");
    try testing.expect(!c.eql(d));
}

test "dynamic equality" {
    const a = atom.AtomName.fromSlice("my-tag");
    const b = atom.AtomName.fromSlice("my-tag");

    try testing.expect(a.eql(b));
}

test "static and dynamic with same bytes are not equal" {
    const static_name = atom.AtomName.fromSlice("div");

    const dynamic_name: atom.AtomName = .{
        .dynamic = "div",
    };

    try testing.expect(!static_name.eql(dynamic_name));
}

