const std = @import("std");
const properties = @import("../css/properties/types.zig");
const Specificity = @import("../css/selectors/Specificity.zig");
pub const MatchedRule = @import("cascade/MatchedRule.zig").MatchedRule;
pub const Origin = @import("cascade/MatchedRule.zig").Origin;

/// Winners borrow prepared declarations. Null means no cascaded declaration.
pub const CascadedDeclarations = std.EnumArray(properties.PropertyId, ?*const properties.Declaration);

/// Pick the winning declaration for each CSS property.
/// When two declarations have the same priority, the later one wins.
/// This only handles ordinary stylesheet rules.
/// FIXME: Inline styles, layers, animations, and transitions are not handled yet.
pub fn cascade(matched_rules: []const MatchedRule) CascadedDeclarations {
    var winners = CascadedDeclarations.initFill(null);
    var priorities = std.EnumArray(properties.PropertyId, ?Priority).initFill(null);
    for (matched_rules) |rule| {
        for (rule.declarations) |*declaration| {
            const priority: Priority = .{
                .important = declaration.important,
                .origin = rule.origin,
                .specificity = rule.specificity,
            };
            if (priorities.get(declaration.property)) |previous| {
                if (!priority.overrides(previous)) continue;
            }
            winners.set(declaration.property, declaration);
            priorities.set(declaration.property, priority);
        }
    }
    for (winners.values) |winner| {
        const declaration = winner orelse continue;
        if (declaration.value == .css_wide) switch (declaration.value.css_wide) {
            .revert => @panic("TODO: cascade origin rollback for revert"),
            .revert_layer => @panic("TODO: cascade layer rollback for revert-layer"),
            else => {},
        };
    }
    return winners;
}

const Priority = struct {
    important: bool,
    origin: Origin,
    specificity: Specificity,

    // https://www.w3.org/TR/css-cascade-5/#cascade-sort
    fn overrides(self: Priority, previous: Priority) bool {
        if (self.important != previous.important) return self.important;
        if (self.origin != previous.origin) return if (self.important)
            @intFromEnum(self.origin) < @intFromEnum(previous.origin)
        else
            @intFromEnum(self.origin) > @intFromEnum(previous.origin);
        return self.specificity.order(previous.specificity) != .lt;
    }
};

test "style cascade: source order" {
    const testing = std.testing;
    const first = [_]properties.Declaration{
        .{
            .property = .width,
            .value = .{
                .size = .{ .length_percentage = .{ .percentage = 10 } },
            },
        },
        .{
            .property = .height,
            .value = .{ .size = .auto },
            .important = true,
        },
    };
    const second = [_]properties.Declaration{
        .{
            .property = .width,
            .value = .{
                .size = .{ .length_percentage = .{ .percentage = 20 } },
            },
        },
        .{
            .property = .width,
            .value = .{
                .size = .{ .length_percentage = .{ .percentage = 30 } },
            },
        },
        .{
            .property = .height,
            .value = .{
                .size = .{ .length_percentage = .{ .percentage = 50 } },
            },
        },
    };
    var rules = [_]MatchedRule{
        .{
            .declarations = &first,
            .specificity = .{ .c = 1 },
            .origin = .author,
        },
        .{
            .declarations = &second,
            .specificity = .{ .c = 1 },
            .origin = .author,
        },
    };

    // Equal priority: later rule wins, then its last width declaration wins.
    const winners = cascade(&rules);
    try testing.expect(winners.get(.width).? == &second[1]);

    // A later normal declaration does not override an important declaration.
    try testing.expect(winners.get(.height).? == &first[1]);

    // Lower specificity cannot win merely by appearing later.
    rules[1].specificity = .{};
    try testing.expect(cascade(&rules).get(.width).? == &first[0]);
}
