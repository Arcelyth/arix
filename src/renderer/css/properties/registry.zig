const std = @import("std");
const String = @import("../String.zig");
const Stream = @import("../syntax/ComponentValueStream.zig");
const size = @import("../values/specified/size.zig");
const computed = @import("../values/computed.zig");
const Value = @import("types.zig").Value;
const margin = @import("../values/specified/margin.zig");
const display = @import("../values/specified/display.zig");
const length_percentage = @import("../values/specified/length_percentage.zig");

pub const definitions = .{
    .width = preferred_size,
    .height = preferred_size,

    .display = display_entry,
    .margin_top = margin_side,
    .margin_right = margin_side,
    .margin_bottom = margin_side,
    .margin_left = margin_side,
    .padding_top = padding_side,
    .padding_right = padding_side,
    .padding_bottom = padding_side,
    .padding_left = padding_side,
};

// https://www.w3.org/TR/css-sizing-3/#preferred-size-properties
const preferred_size = .{
    .parse = &parseSize,
    .value_tag = @as(std.meta.Tag(Value), .size),
    .initial = @as(computed.Size, .auto),
    .inherited = false,
    .compute = &computed.Size.fromSpecified,
};

// https://www.w3.org/TR/css-display-3/#the-display-properties
const display_entry = .{
    .parse = &parseDisplay,
    .value_tag = @as(std.meta.Tag(Value), .display),
    .initial = @as(computed.Display, .{ .box = .{} }),
    .inherited = false,
    .compute = &computed.Display.fromSpecified,
};

// https://www.w3.org/TR/css-box-3/#margin-physical
const margin_side = .{
    .parse = &parseMargin,
    .value_tag = @as(std.meta.Tag(Value), .margin),
    .initial = @as(computed.Margin, .{
        .length_percentage = .{ .length = 0 },
    }),
    .inherited = false,
    .compute = &computed.Margin.fromSpecified,
};

// https://www.w3.org/TR/css-box-3/#padding-physical
const padding_side = .{
    .parse = &parsePadding,
    .value_tag = @as(std.meta.Tag(Value), .padding),
    .initial = @as(computed.LengthPercentage, .{ .length = 0 }),
    .inherited = false,
    .compute = &computed.LengthPercentage.fromSpecified,
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

fn parseMargin(input: *Stream) ?Value {
    return .{ .margin = margin.parse(input) orelse return null };
}

fn parsePadding(input: *Stream) ?Value {
    return .{ .padding = length_percentage.parse(input, .non_negative) orelse return null };
}

fn parseDisplay(input: *Stream) ?Value {
    return .{ .display = display.parse(input) orelse return null };
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
