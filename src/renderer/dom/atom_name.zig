const std = @import("std");

pub const static_atom_names: []const [:0]const u8 = &.{
    "a", "abbr", "address", "area", "article", "aside", "audio", "b", "base", "html", "div", "span"
};

pub const AtomTag = block: {
    var values: [static_atom_names.len]u16 = undefined;
    for (0..static_atom_names.len) |i| {
        values[i] = i;
    }
    const const_values = values;

    break :block @Enum(
        u16,
        .exhaustive,
        static_atom_names,
        &const_values,
    );
};

pub const AtomNameMap = std.StaticStringMap(AtomTag).initComptime(block: {
    var kvs: [static_atom_names.len]struct { []const u8, AtomTag } = undefined;
    for (static_atom_names, 0..) |name, i| {
        kvs[i] = .{ name, @enumFromInt(i) };
    }
    break :block kvs;
});

pub const AtomName = union(enum) {
    static: AtomTag,
    dynamic: []const u8,

    pub inline fn fromSlice(slice: []const u8) AtomName {
        if (AtomNameMap.get(slice)) |tag| {
            return .{ .static = tag };
        }
        return .{ .dynamic = slice };
    }

    pub inline fn eql(self: AtomName, other: AtomName) bool {
        if (self == .static and other == .static) {
            return self.static == other.static;
        }
        if (self == .dynamic and other == .dynamic) {
            return std.mem.eql(u8, self.dynamic, other.dynamic);
        }
        return false;
    }

    pub inline fn is(self: AtomName, tag: AtomTag) bool {
        return self == .static and self.static == tag;
    }
};
