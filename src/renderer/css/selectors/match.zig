const std = @import("std");
const ComponentValueStream = @import("../syntax/ComponentValueStream.zig");
const types = @import("types.zig");

pub const Error = std.mem.Allocator.Error || error{ Syntax, NotImplemented };

// https://www.w3.org/TR/selectors-4/#typedef-selector-list
pub fn matchSelectorList(allocator: std.mem.Allocator, input: *ComponentValueStream) Error!types.SelectorList {
    var selectors: std.ArrayList(types.ComplexSelector) = .empty;
    errdefer {
        for (selectors.items) |selector| {
            for (selector.parts) |part| switch (part.selector) {
                .compound => |compound| allocator.free(compound.simple_selectors),
                .pseudo_compound => |compound| allocator.free(compound.pseudo_classes),
            };
            allocator.free(selector.parts);
        }
        selectors.deinit(allocator);
    }

    while (true) {
        input.discardWhitespace();
        const first = input.peek() orelse return error.Syntax;
        if (first.* == .preserved_token and first.preserved_token == .comma)
            return error.Syntax;

        // Reserve before matching so ownership transfers without a fallible append.
        try selectors.ensureUnusedCapacity(allocator, 1);
        selectors.appendAssumeCapacity(try matchComplexSelector(allocator, input));

        input.discardWhitespace();
        const separator = input.consume() orelse return selectors.toOwnedSlice(allocator);
        if (separator.* != .preserved_token or separator.preserved_token != .comma)
            return error.Syntax;
    }
}

fn matchComplexSelector(allocator: std.mem.Allocator, input: *ComponentValueStream) Error!types.ComplexSelector {
    _ = allocator;
    _ = input;
}
