const std = @import("std");
const String = @import("../String.zig");
const Stream = @import("../syntax/ComponentValueStream.zig");
const size = @import("../values/specified/size.zig");
const Value = @import("types.zig").Value;

// Register each CSS name and its value parser.
const definitions = .{
    .width = &parseSize,
    .height = &parseSize,
};

pub const PropertyId = std.meta.FieldEnum(@TypeOf(definitions));

const names = blk: {
    const fields = std.meta.fields(PropertyId);
    var entries: [fields.len]struct { []const u8, PropertyId } = undefined;
    for (fields, 0..) |field, i| entries[i] = .{ field.name, @enumFromInt(field.value) };
    break :blk std.StaticStringMap(PropertyId).initComptime(entries);
};

// Indexed by the generated ID, not searched at runtime.
const parsers = blk: {
    const fields = std.meta.fields(PropertyId);
    var entries: [fields.len]*const fn (*Stream) ?Value = undefined;
    for (fields) |field| entries[field.value] = @field(definitions, field.name);
    break :blk entries;
};

pub fn fromName(name: String) ?PropertyId {
    var lower: [names.max_len]u8 = undefined;
    return names.get(name.toAsciiLower(&lower) orelse return null);
}

/// Parse the property's grammar; CSS-wide keywords are handled by the caller.
pub fn parseValue(id: PropertyId, input: *Stream) ?Value {
    return parsers[@intFromEnum(id)](input);
}

fn parseSize(input: *Stream) ?Value {
    return .{ .size = size.parse(input) orelse return null };
}

test "properties registry: lookup" {
    inline for (std.meta.fields(PropertyId)) |field| {
        const expected: ?PropertyId = @enumFromInt(field.value);
        try std.testing.expectEqual(expected, fromName(String.fromSource(field.name)));
    }
    try std.testing.expectEqual(PropertyId.width, fromName(String.fromSource("WiDtH")).?);
    try std.testing.expectEqual(PropertyId.height, fromName(String.fromSource("HEIGHT")).?);
    for ([_][]const u8{ "", "widt", "widths", "unknown", "--width", "wídth" }) |name| {
        try std.testing.expectEqual(null, fromName(String.fromSource(name)));
    }
}
