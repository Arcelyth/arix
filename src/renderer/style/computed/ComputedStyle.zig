const ComputedStyle = @This();
const std = @import("std");
const computed = @import("../../css/values/computed.zig");
const properties = @import("../../css/properties/types.zig");
const registry = @import("../../css/properties/registry.zig");
const cascade = @import("../cascade.zig");
pub const Context = computed.Context;

values: registry.ComputedValues,

pub fn init(context: *const Context) ComputedStyle {
    var result: ComputedStyle = .{ .values = undefined };
    inline for (@typeInfo(properties.PropertyId).@"enum".field_names) |name| {
        @field(result.values, name) = registry.initialValue(name, context);
    }
    return result;
}

// See https://www.w3.org/TR/css-cascade-5/#inheriting for inheriting rules.
pub fn compute(
    winners: *const cascade.CascadedDeclarations,
    parent: ?*const ComputedStyle,
    context: *const Context,
) ComputedStyle {
    const initial = init(context);
    const inherited = parent orelse &initial;
    var result: ComputedStyle = .{ .values = undefined };
    var compute_context = context.*;
    compute_context.inherited_style = &inherited.values;
    compute_context.is_root = parent == null;

    for (std.enums.values(properties.PropertyId)) |id| {
        computers[@backingInt(id)](&result, winners.get(id), inherited, &compute_context);
    }
    return result;
}

/// Generate separate handlers.
const computers = blk: {
    const fields = @typeInfo(properties.PropertyId).@"enum";
    var entries: [fields.field_names.len]*const fn (
        *ComputedStyle,
        ?*const properties.Declaration,
        *const ComputedStyle,
        *Context,
    ) void = undefined;
    for (fields.field_names, fields.field_values) |name, value| {
        entries[value] = struct {
            fn computeProperty(
                style: *ComputedStyle,
                winner: ?*const properties.Declaration,
                parent: *const ComputedStyle,
                context: *Context,
            ) void {
                const definition = @field(registry.definitions, name);
                const dest = &@field(style.values, name);
                const inherited = @field(parent.values, name);
                const initial = registry.initialValue(name, context);

                dest.* = if (definition.inherited) inherited else initial;
                if (winner) |declaration| {
                    dest.* = if (declaration.value == .css_wide) switch (declaration.value.css_wide) {
                        .initial => initial,
                        .inherit => inherited,
                        .unset => dest.*,
                        .revert => @panic("TODO: cascade origin rollback for revert"),
                        .revert_layer => @panic("TODO: cascade layer rollback for revert-layer"),
                        .revert_rule => @panic("TODO: cascade rule rollback for revert-rule"),
                    } else definition.compute(@field(declaration.value, @tagName(definition.value_tag)), context);
                }
                if (@hasField(@TypeOf(definition), "update_context")) definition.update_context(dest.*, context);
            }
        }.computeProperty;
    }
    break :blk entries;
};

test "style computed ComputedStyle: lengths, percentages and defaults" {
    const testing = std.testing;
    const context: Context = .{
        .font_size = 20,
        .default_font_size = 20,
        .root_font_size = 16,
        .x_height = 9,
        .zero_advance = 11,
        .viewport_width = 800,
        .viewport_height = 600,
    };
    const declarations = [_]properties.Declaration{
        .{
            .property = .width,
            .value = .{
                .size = .{
                    .length_percentage = .{
                        .length = .{ .value = 2, .unit = .em },
                    },
                },
            },
        },
        .{
            .property = .height,
            .value = .{
                .size = .{ .length_percentage = .{ .percentage = 50 } },
            },
        },
    };
    var winners = cascade.CascadedDeclarations.initFill(null);
    winners.set(.width, &declarations[0]);
    winners.set(.height, &declarations[1]);

    const style = compute(&winners, null, &context);
    // 2em becomes 40 CSS pixels; 50% remains a percentage until layout.
    var expected = init(&context);
    expected.values.width = .{ .length_percentage = .{ .length = 40 } };
    expected.values.height = .{ .length_percentage = .{ .percentage = 50 } };
    try testing.expectEqualDeep(expected.values, style.values);

    // Width and height default to auto, not the parent's values.
    const empty = cascade.CascadedDeclarations.initFill(null);
    try testing.expectEqualDeep(
        init(&context).values,
        compute(&empty, &style, &context).values,
    );
}
