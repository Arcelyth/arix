//! Parsing selectors.
//! https://drafts.csswg.org/cssom/#parsing-selectors
const std = @import("std");
const types = @import("../selectors/types.zig");
const parsing = @import("../selectors/parse.zig");
const ns = @import("../namespace.zig");
const String = @import("../String.zig");
const syntax = @import("../syntax.zig");
const Value = @import("../syntax/parsing_results.zig").ComponentValue;
const Token = @import("../syntax/token.zig").Token;
const serialize = @import("serialize.zig");

/// Parses a group of selectors using the stylesheet's namespace context.
/// https://drafts.csswg.org/cssom/#parse-a-group-of-selectors
pub fn parseGroup(allocator: std.mem.Allocator, input: *syntax.ComponentValueStream, context: parsing.Context) !?types.SelectorList {
    const start = input.index;
    const list = try parsing.parseSelectorList(allocator, input, context) orelse return null;
    for (list.selectors) |entry| {
        for (entry.components) |component| {
            if (component != .simple) continue;
            const prefix = switch (component.simple) {
                .type_selector => |name| name.namespace,
                .universal => |p| p,
                .attribute => |attr| attr.name.namespace,
                else => continue,
            };
            if (prefix == .named and context.namespaces.lookup(prefix.named) == null) {
                list.deinit(allocator);
                input.restore(start);
                return null;
            }
        }
    }
    return list;
}
