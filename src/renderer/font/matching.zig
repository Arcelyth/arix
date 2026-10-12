const std = @import("std");
pub const Style = @import("../css/values/computed/font_style.zig").FontStyle;

/// CSS face properties, before applying the requested font size.
pub const Attributes = struct {
    width: f64 = 100,
    style: Style = .normal,
    weight: f64 = 400,
};

const Rank = struct {
    group: u8,
    distance: f64,

    fn compare(a: Rank, b: Rank) std.math.Order {
        const group = std.math.order(a.group, b.group);
        return if (group == .eq) std.math.order(a.distance, b.distance) else group;
    }
};

/// Width, then style, then weight. Equal faces keep source order.
pub fn compare(request: Attributes, a: Attributes, b: Attributes) std.math.Order {
    const width = Rank.compare(widthRank(request.width, a.width), widthRank(request.width, b.width));
    if (width != .eq) return width;
    const style = Rank.compare(styleRank(request.style, a.style), styleRank(request.style, b.style));
    if (style != .eq) return style;
    return Rank.compare(weightRank(request.weight, a.weight), weightRank(request.weight, b.weight));
}

fn widthRank(request: f64, value: f64) Rank {
    const preferred = if (request <= 100) value <= request else value >= request;
    return .{
        .group = if (preferred) 0 else 1,
        .distance = @abs(value - request),
    };
}

fn weightRank(request: f64, value: f64) Rank {
    if (request >= 400 and request <= 500) {
        return .{
            .group = if (value >= request and value <= 500) 0 else if (value < request) 1 else 2,
            .distance = @abs(value - request),
        };
    }
    const preferred = if (request < 400) value <= request else value >= request;
    return .{
        .group = if (preferred) 0 else 1,
        .distance = @abs(value - request),
    };
}

fn styleRank(request: Style, value: Style) Rank {
    return switch (request) {
        .normal => normalRank(value),
        .italic, .left => italicRank(value, 1),
        .right => italicRank(value, -1),
        .oblique => |angle| obliqueRank(value, angle),
    };
}

fn italicValue(style: Style) ?f64 {
    return switch (style) {
        .italic, .left => 1,
        .right => -1,
        else => null,
    };
}

fn obliqueValue(style: Style) ?f64 {
    return switch (style) {
        .normal => 0,
        .oblique => |angle| angle,
        else => null,
    };
}

fn normalRank(style: Style) Rank {
    if (obliqueValue(style)) |angle|
        return .{
            .group = if (angle >= 0) 0 else 2,
            .distance = @abs(angle),
        };
    const italic = italicValue(style).?;
    return .{
        .group = if (italic >= 0) 1 else 3,
        .distance = @abs(italic),
    };
}

fn italicRank(style: Style, direction: f64) Rank {
    if (italicValue(style)) |value|
        return .{
            .group = if (value * direction > 0) 0 else 3,
            .distance = @abs(value - direction),
        };
    const angle = obliqueValue(style).? * direction;
    if (angle >= 11)
        return .{ .group = 1, .distance = angle - 11 };

    if (angle > 0)
        return .{ .group = 2, .distance = 11 - angle };
    return .{ .group = 4, .distance = -angle };
}

fn obliqueRank(style: Style, request: f64) Rank {
    const direction: f64 = if (request < 0) -1 else 1;
    const target = @abs(request);
    if (italicValue(style)) |value|
        return .{
            .group = if (value * direction > 0) 3 else 5,
            .distance = 0,
        };
    const angle = obliqueValue(style).? * direction;
    if (angle == target) return .{ .group = 0, .distance = 0 };
    if (angle <= 0) return .{ .group = 4, .distance = -angle };

    const preferred = if (target >= 11) angle >= target else angle <= target;
    return .{
        .group = if (preferred) 1 else 2,
        .distance = @abs(angle - target),
    };
}
