const std = @import("std");
const Allocator = std.mem.Allocator;
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
const font_family = @import("../values/specified/font_family.zig");
const font_size = @import("../values/specified/font_size.zig");
const font_weight = @import("../values/specified/font_weight.zig");
const font_style = @import("../values/specified/font_style.zig");
const white_space = @import("../values/specified/white_space.zig");
const line_height = @import("../values/specified/line_height.zig");
const shorthand = @import("shorthand.zig");
const Shorthand = shorthand.Shorthand;
const shorthands = shorthand.shorthands;

pub const Property = union(enum) {
    longhand: PropertyId,
    shorthand: shorthand.Shorthand,
};

pub const definitions = .{
    // Font size must be computed before lengths that use em.
    .font_size = font_size_entry,
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

    .font_family = font_family_entry,
    .font_weight = font_weight_entry,
    .font_style = font_style_entry,

    .line_height = line_height_entry,
    .white_space = white_space_entry,
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

const font_family_entry = .{
    .parse = &parseFontFamily,
    .value_tag = @as(std.meta.Tag(Value), .font_family),
    .initial = computed.font_family.initial,
    .inherited = true,
    .compute = &computed.font_family.fromSpecified,
};

const font_size_entry = .{
    .parse = &parseFontSize,
    .value_tag = @as(std.meta.Tag(Value), .font_size),
    .initial = computed.font_size.initial,
    .inherited = true,
    .compute = &computed.font_size.fromSpecified,
    .update_context = &computed.font_size.updateContext,
};

const font_weight_entry = .{
    .parse = &parseFontWeight,
    .value_tag = @as(std.meta.Tag(Value), .font_weight),
    .initial = @as(f64, 400),
    .inherited = true,
    .compute = &computed.font_weight.fromSpecified,
};

const font_style_entry = .{
    .parse = &parseFontStyle,
    .value_tag = @as(std.meta.Tag(Value), .font_style),
    .initial = @as(computed.font_style.FontStyle, .normal),
    .inherited = true,
    .compute = &computed.font_style.fromSpecified,
};

const line_height_entry = .{
    .parse = &parseLineHeight,
    .value_tag = @as(std.meta.Tag(Value), .line_height),
    .initial = @as(computed.line_height.LineHeight, .normal),
    .inherited = true,
    .compute = &computed.line_height.fromSpecified,
};

const white_space_entry = .{
    .parse = &parseWhiteSpace,
    .value_tag = @as(std.meta.Tag(Value), .white_space),
    .initial = @as(computed.white_space.WhiteSpace, .normal),
    .inherited = true,
    .compute = &computed.white_space.fromSpecified,
};

pub const PropertyId = std.meta.FieldEnum(@TypeOf(definitions));

const names = blk: {
    const fields = @typeInfo(PropertyId).@"enum";
    const shorthand_fields = @typeInfo(std.meta.FieldEnum(@TypeOf(shorthands))).@"enum".field_names;
    var entries: [fields.field_names.len + shorthand_fields.len]struct { []const u8, Property } = undefined;

    for (fields.field_names, fields.field_values, 0..) |field_name, field_value, i| {
        const name = cssName(field_name);
        entries[i] = .{ &name, .{ .longhand = @fromBackingInt(@intCast(field_value)) } };
    }

    for (shorthand_fields, 0..) |field_name, i| {
        const name = cssName(field_name);
        entries[fields.field_names.len + i] = .{
            &name,
            .{ .shorthand = @field(shorthands, field_name) },
        };
    }
    break :blk std.StaticStringMap(Property).initComptime(entries);
};

inline fn cssName(comptime field_name: []const u8) [field_name.len]u8 {
    var bytes: [field_name.len]u8 = undefined;
    for (field_name, 0..) |byte, i| bytes[i] = if (byte == '_') '-' else byte;
    return bytes;
}

const ParseResult = ?Value;

// Indexed by the generated ID, not searched at runtime.
const parsers = blk: {
    const fields = @typeInfo(PropertyId).@"enum";
    var entries: [fields.field_names.len]*const fn (Allocator, *Stream) ParseResult = undefined;
    for (fields.field_names, fields.field_values) |name, value| entries[value] = @field(definitions, name).parse;
    break :blk entries;
};

pub fn fromName(name: String) ?Property {
    var lower: [names.max_len]u8 = undefined;
    return names.get(name.toAsciiLower(&lower) orelse return null);
}

/// Parse the property's grammar; CSS-wide keywords are handled by the caller.
pub fn parseValue(allocator: Allocator, id: PropertyId, input: *Stream) ParseResult {
    return parsers[@backingInt(id)](allocator, input);
}

fn parseSize(_: Allocator, input: *Stream) ParseResult {
    return .{ .size = size.parse(input) orelse return null };
}

fn parseMargin(_: Allocator, input: *Stream) ParseResult {
    return .{ .margin = margin.parse(input) orelse return null };
}

fn parsePadding(_: Allocator, input: *Stream) ParseResult {
    return .{ .padding = length_percentage.parse(input, .non_negative) orelse return null };
}

fn parseDisplay(_: Allocator, input: *Stream) ParseResult {
    return .{ .display = display.parse(input) orelse return null };
}

fn parseColor(_: Allocator, input: *Stream) ParseResult {
    return .{ .color = color.parseComponent(input) orelse return null };
}

fn parseBorderWidth(_: Allocator, input: *Stream) ParseResult {
    return .{ .line_width = line_width.parse(input) orelse return null };
}

fn parseBorderStyle(_: Allocator, input: *Stream) ParseResult {
    return .{ .line_style = line_style.parse(input) orelse return null };
}

fn parseFontFamily(allocator: Allocator, input: *Stream) ParseResult {
    return .{ .font_family = (font_family.parse(allocator, input) catch @panic("OOM")) orelse return null };
}

fn parseFontSize(_: Allocator, input: *Stream) ParseResult {
    return .{ .font_size = font_size.parse(input) orelse return null };
}

fn parseFontWeight(_: Allocator, input: *Stream) ParseResult {
    return .{ .font_weight = font_weight.parse(input) orelse return null };
}

fn parseFontStyle(_: Allocator, input: *Stream) ParseResult {
    return .{ .font_style = font_style.parse(input) orelse return null };
}

fn parseLineHeight(_: Allocator, input: *Stream) ParseResult {
    return .{ .line_height = line_height.parse(input) orelse return null };
}

fn parseWhiteSpace(_: Allocator, input: *Stream) ParseResult {
    return .{ .white_space = white_space.parse(input) orelse return null };
}

fn InitialType(comptime initial: anytype) type {
    return switch (@typeInfo(@TypeOf(initial))) {
        .@"fn" => |function| function.return_type.?,
        else => @TypeOf(initial),
    };
}

/// Initial values may be constants or functions of the computation context.
pub fn initialValue(comptime name: []const u8, context: *const computed.Context) InitialType(@field(definitions, name).initial) {
    const initial = @field(definitions, name).initial;
    return if (@typeInfo(@TypeOf(initial)) == .@"fn") initial(context) else initial;
}

/// One field per property, with its concrete computed type and initial default.
/// ComputedStyle uses this struct.
pub const ComputedValues = blk: {
    const properties = @typeInfo(PropertyId).@"enum".field_names;
    var field_types: [properties.len]type = undefined;
    var field_attrs: [properties.len]std.lang.Type.Struct.FieldAttributes = undefined;

    for (properties, 0..) |property, i| {
        const definition = @field(definitions, property);
        const initial = definition.initial;
        field_types[i] = InitialType(initial);
        field_attrs[i] = .{ .default_value_ptr = if (@typeInfo(@TypeOf(initial)) == .@"fn") null else &initial };
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
    for (names.keys(), names.values()) |name, property| {
        try std.testing.expectEqualDeep(@as(?Property, property), fromName(String.fromSource(name)));
    }
    try std.testing.expectEqual(PropertyId.width, fromName(String.fromSource("WiDtH")).?.longhand);
    try std.testing.expectEqual(PropertyId.height, fromName(String.fromSource("HEIGHT")).?.longhand);
    try std.testing.expectEqual(PropertyId.padding_left, fromName(String.fromSource("PaDdInG-LeFt")).?.longhand);
    try std.testing.expectEqual(PropertyId.margin_top, fromName(String.fromSource("margin-top")).?.longhand);
    try std.testing.expectEqualDeep(shorthands.border_width, fromName(String.fromSource("BoRdEr-WiDtH")).?.shorthand);
    for ([_][]const u8{ "", "widt", "widths", "unknown", "--width", "wídth", "padding_left", "border_width" }) |name| {
        try std.testing.expectEqual(null, fromName(String.fromSource(name)));
    }
}
