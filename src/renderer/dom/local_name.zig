const std = @import("std");
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;
const BufferDeque = strale.BufferDeque;

pub const static_local_names: []const [:0]const u8 = &.{ "a", "abbr", "address", "area", "article", "aside", "audio", "b", "base", "html", "div", "span" };

pub const LocalTag = block: {
    var values: [static_local_names.len]u16 = undefined;
    for (0..static_local_names.len) |i| {
        values[i] = i;
    }
    const const_values = values;

    break :block @Enum(
        u16,
        .exhaustive,
        static_local_names,
        &const_values,
    );
};

pub const LocalNameMap = std.StaticStringMap(LocalTag).initComptime(block: {
    var kvs: [static_local_names.len]struct { []const u8, LocalTag } = undefined;
    for (static_local_names, 0..) |name, i| {
        kvs[i] = .{ name, @enumFromInt(i) };
    }
    break :block kvs;
});

pub const LocalName = union(enum) {
    static: LocalTag,
    dynamic: StraleUtf8Global,

    pub fn deinit(self: *LocalName) void {
        switch (self.*) {
            .static => {},
            .dynamic => |dy| dy.deinit(),
        }
    }

    pub inline fn fromSlice(slice: []const u8) LocalName {
        if (LocalNameMap.get(slice)) |tag| {
            return .{ .static = tag };
        }
        return .{ .dynamic = StraleUtf8Global.fromSlice(slice) };
    }

    pub inline fn eql(self: LocalName, other: LocalName) bool {
        if (self == .static and other == .static) {
            return self.static == other.static;
        }
        if (self == .dynamic and other == .dynamic) {
            return self.dynamic.cmp(other.dynamic);
        }
        return false;
    }

    pub inline fn is(self: LocalName, tag: LocalTag) bool {
        return self == .static and self.static == tag;
    }

    pub fn format(self: LocalName, writer: anytype) !void {
        if (self == .static) try writer.print("{s}", .{@tagName(self.static)}) else try writer.print("{s}", .{self.dynamic.slice()});
    }
};
