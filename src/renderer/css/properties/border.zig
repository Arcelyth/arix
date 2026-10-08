const std = @import("std");
const Allocator = std.mem.Allocator;
const Stream = @import("../syntax/ComponentValueStream.zig");
const types = @import("types.zig");
const registry = @import("registry.zig");

pub fn parseAll(allocator: Allocator, input: *Stream, values: []types.Value) bool {
    if (!parseEdge(allocator, input, values[0..3])) return false;
    for (3..values.len) |i| values[i] = values[i % 3];
    return true;
}

pub fn parseWidths(allocator: Allocator, input: *Stream, values: []types.Value) bool {
    return parseSides(allocator, input, values, .border_top_width);
}

pub fn parseStyles(allocator: Allocator, input: *Stream, values: []types.Value) bool {
    return parseSides(allocator, input, values, .border_top_style);
}

pub fn parseColors(allocator: Allocator, input: *Stream, values: []types.Value) bool {
    return parseSides(allocator, input, values, .border_top_color);
}

fn parseSides(
    allocator: Allocator,
    input: *Stream,
    values: []types.Value,
    property: types.PropertyId,
) bool {
    var count: usize = 0;
    while (!input.empty()) {
        if (count == 4) return false;
        values[count] = registry.parseValue(allocator, property, input) orelse return false;
        count += 1;
        input.discardWhitespace();
    }
    if (count == 0) return false;
    if (count == 1) values[1] = values[0];
    if (count < 3) values[2] = values[0];
    if (count < 4) values[3] = values[1];
    return true;
}

pub fn parseEdge(allocator: Allocator, input: *Stream, values: []types.Value) bool {
    const properties = [_]types.PropertyId{
        .border_top_width,
        .border_top_style,
        .border_top_color,
    };
    values[0] = .{ .line_width = .medium };
    values[1] = .{ .line_style = .none };
    values[2] = .{ .color = .current_color };

    var seen = [3]bool{ false, false, false };
    var any = false;
    while (!input.empty()) {
        var matched = false;
        for (properties, 0..) |property, component| {
            if (seen[component]) continue;

            const start = input.index;
            if (registry.parseValue(allocator, property, input)) |value| {
                values[component] = value;
                seen[component] = true;
                matched = true;
                any = true;
                break;
            }
            input.restore(start);
        }
        if (!matched) return false;
        input.discardWhitespace();
    }
    return any;
}
