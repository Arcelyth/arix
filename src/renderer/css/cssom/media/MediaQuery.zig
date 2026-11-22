//! A parsed media query. Its arena holds the condition tree and its strings.
//! MediaQuery's type definition: https://drafts.csswg.org/mediaqueries-5/#typedef-media-query
const MediaQuery = @This();
const std = @import("std");
const css = @import("../serialize.zig");
const Writer = std.Io.Writer;

arena: std.heap.ArenaAllocator,
modifier: ?enum { not, only } = null,
media_type: []const u8 = "all",
condition: ?Condition = null,

pub const Condition = union(enum) {
    feature: Feature,
    not: *const Condition,
    group: *const Condition,
    @"and": []const Condition,
    @"or": []const Condition,
    general_enclosed: []const u8,

    fn write(self: Condition, writer: *Writer) Writer.Error!void {
        switch (self) {
            .feature => |feature| {
                try writer.writeByte('(');
                try feature.write(writer);
                try writer.writeByte(')');
            },
            .group => |inner| {
                try writer.writeByte('(');
                try inner.write(writer);
                try writer.writeByte(')');
            },
            .not => |inner| {
                try writer.writeAll("not ");
                try inner.write(writer);
            },
            inline .@"and", .@"or" => |terms, tag| for (terms, 0..) |term, i| {
                if (i != 0) try writer.writeAll(" " ++ @tagName(tag) ++ " ");
                try term.write(writer);
            },
            .general_enclosed => |source| try writer.writeAll(source),
        }
    }
};

pub const Value = union(enum) {
    ident: []const u8,
    number: f64,
    dimension: struct {
        number: f64,
        unit: []const u8,
    },
    ratio: struct {
        numerator: f64,
        denominator: f64,
    },
    function: []const u8,

    fn write(self: Value, writer: *Writer) Writer.Error!void {
        switch (self) {
            .ident => |name| try identifier(writer, name),
            .number => |n| try writer.print("{d}", .{n}),
            .dimension => |d| {
                try writer.print("{d}", .{d.number});
                try identifier(writer, d.unit);
            },
            .ratio => |r| try writer.print(
                "{d} / {d}",
                .{ r.numerator, r.denominator },
            ),
            .function => |source| try writer.writeAll(source),
        }
    }
};

pub const Comparison = enum {
    @"<",
    @"<=",
    @"=",
    @">=",
    @">",
};

pub const Bound = struct {
    operator: Comparison,
    value: Value,
};

pub const Feature = struct {
    name: []const u8,
    form: union(enum) {
        boolean,
        plain: Value,
        range: struct {
            before: ?Bound = null,
            after: ?Bound = null,
        },
    },

    fn write(self: Feature, writer: *Writer) Writer.Error!void {
        if (self.form == .range) {
            if (self.form.range.before) |bound| {
                try bound.value.write(writer);
                try writer.print(" {s} ", .{@tagName(bound.operator)});
            }
        }
        try identifier(writer, self.name);
        switch (self.form) {
            .boolean => {},
            .plain => |value| {
                try writer.writeAll(": ");
                try value.write(writer);
            },
            .range => |range| if (range.after) |bound| {
                try writer.print(" {s} ", .{@tagName(bound.operator)});
                try bound.value.write(writer);
            },
        }
    }
};

// Names have already been decoded by the CSS tokenizer.
fn identifier(writer: *Writer, name: []const u8) Writer.Error!void {
    css.identifier(writer, name) catch |err| switch (err) {
        error.InvalidUtf8 => unreachable,
        else => |e| return e,
    };
}

pub fn deinit(self: *MediaQuery) void {
    self.arena.deinit();
}

/// Writes the query in CSSOM form.
/// https://drafts.csswg.org/cssom/#serialize-a-media-query
pub fn serialize(self: *const MediaQuery, writer: *Writer) Writer.Error!void {
    if (self.modifier == .not) try writer.writeAll("not ");
    if (self.condition == null) return identifier(writer, self.media_type);
    if (self.modifier == .not or !std.mem.eql(u8, self.media_type, "all")) {
        try identifier(writer, self.media_type);
        try writer.writeAll(" and ");
    }
    try self.condition.?.write(writer);
}

/// Returns the serialized query. Free the result with allocator.free.
pub fn toString(self: *const MediaQuery, allocator: std.mem.Allocator) ![]u8 {
    var output: Writer.Allocating = .init(allocator);
    defer output.deinit();
    try self.serialize(&output.writer);
    return output.toOwnedSlice();
}

/// Compares the two CSSOM serializations byte for byte.
/// https://drafts.csswg.org/cssom/#compare-media-queries
pub fn matches(self: *const MediaQuery, other: *const MediaQuery) !bool {
    const allocator = self.arena.child_allocator;
    const left = try self.toString(allocator);
    defer allocator.free(left);
    const right = try other.toString(allocator);
    defer allocator.free(right);
    return std.mem.eql(u8, left, right);
}
