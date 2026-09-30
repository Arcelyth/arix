const ComputedStyle = @This();
const std = @import("std");
const computed = @import("../../css/values/computed.zig");
const properties = @import("../../css/properties/types.zig");
const registry = @import("../../css/properties/registry.zig");
const cascade = @import("../cascade.zig");
pub const Context = computed.Context;

values: registry.ComputedValues = .{},

// See https://www.w3.org/TR/css-cascade-5/#inheriting for inheriting rules.
pub fn compute(
    winners: *const cascade.CascadedDeclarations,
    parent: ?*const ComputedStyle,
    context: *const Context,
) ComputedStyle {
    const initial: ComputedStyle = .{};
    const inherited = parent orelse &initial;
    var result: ComputedStyle = .{};

    for (std.enums.values(properties.PropertyId)) |id| {
        computers[@intFromEnum(id)](&result, winners.get(id), inherited, context);
    }
    return result;
}

/// Generate separate handlers.
const computers = blk: {
    const fields = std.meta.fields(properties.PropertyId);
    var entries: [fields.len]*const fn (
        *ComputedStyle,
        ?*const properties.Declaration,
        *const ComputedStyle,
        *const Context,
    ) void = undefined;
    for (fields) |field| {
        entries[field.value] = struct {
            fn computeProperty(
                style: *ComputedStyle,
                winner: ?*const properties.Declaration,
                parent: *const ComputedStyle,
                context: *const Context,
            ) void {
                const definition = @field(registry.definitions, field.name);
                const dest = &@field(style.values, field.name);
                const inherited = @field(parent.values, field.name);

                dest.* = if (definition.inherited) inherited else definition.initial;
                const declaration = winner orelse return;
                dest.* = if (declaration.value == .css_wide) switch (declaration.value.css_wide) {
                    .initial => definition.initial,
                    .inherit => inherited,
                    .unset => dest.*,
                    .revert => @panic("TODO: cascade origin rollback for revert"),
                    .revert_layer => @panic("TODO: cascade layer rollback for revert-layer"),
                } else definition.compute(@field(declaration.value, @tagName(definition.value_tag)), context);
            }
        }.computeProperty;
    }
    break :blk entries;
};
