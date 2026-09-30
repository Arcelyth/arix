const std = @import("std");
const String = @import("../String.zig");
const Stream = @import("../syntax/ComponentValueStream.zig");
const size = @import("../values/specified/size.zig");
const computed = @import("../values/computed.zig");
const Value = @import("types.zig").Value;

pub const definitions = .{
    .width = preferred_size,
    .height = preferred_size,
};

// https://www.w3.org/TR/css-sizing-3/#preferred-size-properties
const preferred_size = .{
    .parse = &parseSize,
    .value_tag = @as(std.meta.Tag(Value), .size),
    .initial = @as(computed.Size, .auto),
    .inherited = false,
    .compute = &computed.Size.fromSpecified,
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
    for (fields) |field| entries[field.value] = @field(definitions, field.name).parse;
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

/// One field per property, with its concrete computed type and initial default.
/// ComputedStyle uses this struct.
pub const ComputedValues = blk: {
    const properties = std.meta.fields(PropertyId);
    var field_types: [properties.len]type = undefined;
    var field_attrs: [properties.len]std.builtin.Type.StructField.Attributes = undefined;

    for (properties, 0..) |property, i| {
        const initial = @field(definitions, property.name).initial;
        field_types[i] = @TypeOf(initial);
        field_attrs[i] = .{ .default_value_ptr = &initial };
    }
    break :blk @Struct(
        .auto,
        null,
        std.meta.fieldNames(PropertyId),
        &field_types,
        &field_attrs,
    );
};

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
