const std = @import("std");
const String = @import("../String.zig");
const Stream = @import("../syntax/ComponentValueStream.zig");
const size = @import("../values/specified/size.zig");
const computed = @import("../values/computed.zig");
const Value = @import("types.zig").Value;
const margin = @import("../values/specified/margin.zig");
const display = @import("../values/specified/display.zig");
const length_percentage = @import("../values/specified/length_percentage.zig");
const color = @import("../color/parse.zig");
const line_width = @import("../values/specified/line_width.zig");
const line_style = @import("../values/specified/line_style.zig");
const shorthand = @import("shorthand.zig");

pub const definitions = .{
    .width = preferred_size,
    .height = preferred_size,

    .display = display_entry,
    .color = foreground_color,
    .background_color = background_color,
    .margin_top = margin_side,
    .margin_right = margin_side,
    .margin_bottom = margin_side,
    .margin_left = margin_side,
    .padding_top = padding_side,
    .padding_right = padding_side,
    .padding_bottom = padding_side,
    .padding_left = padding_side,

    .border_top_width = border_width,
    .border_right_width = border_width,
    .border_bottom_width = border_width,
    .border_left_width = border_width,
    .border_top_style = border_style,
    .border_right_style = border_style,
    .border_bottom_style = border_style,
    .border_left_style = border_style,
    .border_top_color = border_color,
    .border_right_color = border_color,
    .border_bottom_color = border_color,
    .border_left_color = border_color,
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

// https://www.w3.org/TR/css-backgrounds-3/#background-color
const background_color = .{
    .parse = &parseColor,
    .value_tag = @as(std.meta.Tag(Value), .color),
    .initial = computed.Color.transparent,
    .inherited = false,
    .compute = &computed.Color.fromSpecified,
};

const foreground_color = .{
    .parse = &parseColor,
    .value_tag = @as(std.meta.Tag(Value), .color),
    .initial = computed.Color.black,
    .inherited = true,
    .compute = &computed.Color.fromSpecified,
};

const border_width = .{
    .parse = &parseBorderWidth,
    .value_tag = @as(std.meta.Tag(Value), .line_width),
    .initial = @as(f64, 3),
    // The initial border style is none, so the initial computed width is zero.
    .computed_initial = @as(f64, 0),
    .inherited = false,
    .compute = &computed.line_width.fromSpecified,
};

const border_style = .{
    .parse = &parseBorderStyle,
    .value_tag = @as(std.meta.Tag(Value), .line_style),
    .initial = @as(line_style.LineStyle, .none),
    .inherited = false,
    .compute = &computed.line_style.fromSpecified,
};

const border_color = .{
    .parse = &parseColor,
    .value_tag = @as(std.meta.Tag(Value), .color),
    .initial = @as(computed.Color, .current_color),
    .inherited = false,
    .compute = &computed.Color.fromSpecified,
};

pub const PropertyId = std.meta.FieldEnum(@TypeOf(definitions));

const names = blk: {
    const fields = @typeInfo(PropertyId).@"enum";
    var entries: [fields.field_names.len]struct { []const u8, PropertyId } = undefined;
    for (fields.field_names, fields.field_values, 0..) |field_name, field_value, i| {
        // Zig field names use underscores; CSS property names use hyphens.
        const name = name: {
            var bytes: [field_name.len]u8 = undefined;
            for (field_name, 0..) |byte, index| bytes[index] = if (byte == '_') '-' else byte;
            break :name bytes;
        };
        entries[i] = .{ &name, @fromBackingInt(@intCast(field_value)) };
    }
    break :blk std.StaticStringMap(PropertyId).initComptime(entries);
};

// Indexed by the generated ID, not searched at runtime.
const parsers = blk: {
    const fields = @typeInfo(PropertyId).@"enum";
    var entries: [fields.field_names.len]*const fn (*Stream) ?Value = undefined;
    for (fields.field_names, fields.field_values) |name, value| entries[value] = @field(definitions, name).parse;
    break :blk entries;
};

pub fn fromName(name: String) ?PropertyId {
    var lower: [names.max_len]u8 = undefined;
    return names.get(name.toAsciiLower(&lower) orelse return null);
}

/// Parse the property's grammar; CSS-wide keywords are handled by the caller.
pub fn parseValue(id: PropertyId, input: *Stream) ?Value {
    return parsers[@backingInt(id)](input);
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

fn parseColor(input: *Stream) ?Value {
    return .{ .color = color.parseComponent(input) orelse return null };
}

fn parseBorderWidth(input: *Stream) ?Value {
    return .{ .line_width = line_width.parse(input) orelse return null };
}

fn parseBorderStyle(input: *Stream) ?Value {
    return .{ .line_style = line_style.parse(input) orelse return null };
}

/// One field per property, with its concrete computed type and initial default.
/// ComputedStyle uses this struct.
pub const ComputedValues = blk: {
    const properties = @typeInfo(PropertyId).@"enum".field_names;
    var field_types: [properties.len]type = undefined;
    var field_attrs: [properties.len]std.lang.Type.Struct.FieldAttributes = undefined;

    for (properties, 0..) |property, i| {
        const initial = @field(definitions, property).initial;
        field_types[i] = @TypeOf(initial);
        field_attrs[i] = .{ .default_value_ptr = &initial };
    }
    break :blk @Struct(
        .auto,
        null,
        properties,
        &field_types,
        &field_attrs,
    );
};

test "properties registry: lookup" {
    for (names.keys(), names.values()) |name, id| {
        try std.testing.expectEqual(@as(?PropertyId, id), fromName(String.fromSource(name)));
    }
    try std.testing.expectEqual(PropertyId.width, fromName(String.fromSource("WiDtH")).?);
    try std.testing.expectEqual(PropertyId.height, fromName(String.fromSource("HEIGHT")).?);
    try std.testing.expectEqual(PropertyId.padding_left, fromName(String.fromSource("PaDdInG-LeFt")).?);
    try std.testing.expectEqual(PropertyId.margin_top, fromName(String.fromSource("margin-top")).?);
    for ([_][]const u8{ "", "widt", "widths", "unknown", "--width", "wídth", "padding_left" }) |name| {
        try std.testing.expectEqual(null, fromName(String.fromSource(name)));
    }
}
