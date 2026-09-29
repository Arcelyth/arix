const PreparedStylesheet = @This();

const std = @import("std");
const syntax = @import("../css/syntax/parsing_results.zig");
const Stream = @import("../css/syntax/ComponentValueStream.zig");
const selectors = @import("../css/selectors/parse.zig");
const namespace = @import("../css/namespace.zig");
const Specificity = @import("../css/selectors/Specificity.zig");
const PreparedRule = @import("matching.zig").PreparedRule;

rules: []const PreparedRule,
namespaces: *namespace.Context,

/// Parse selector preludes and cache specificity once per stylesheet.
/// Owns selector storage and namespace bindings, but borrows the syntax rules
/// and their strings. Keep the syntax stylesheet and its backing storage alive.
/// Invalid selector lists are discarded by the selector parser.
pub fn init(allocator: std.mem.Allocator, stylesheet: *const syntax.Stylesheet) !PreparedStylesheet {
    const namespaces = try allocator.create(namespace.Context);
    namespaces.* = .{};
    errdefer {
        namespaces.deinit(allocator);
        allocator.destroy(namespaces);
    }

    var rules: std.ArrayList(PreparedRule) = .empty;
    errdefer {
        for (rules.items) |rule| rule.deinit(allocator);
        rules.deinit(allocator);
    }

    for (stylesheet.rules) |*rule| switch (rule.*) {
        .at_rule => |*at_rule| {
            if (!at_rule.name.eqlAscii("namespace")) return error.UnsupportedAtRule;
            _ = try namespaces.consumeRule(allocator, rule, false);
        },
        .qualified_rule => |*qualified| {
            const prepared = (try prepareRule(allocator, qualified, namespaces)) orelse continue;
            errdefer prepared.deinit(allocator);
            if (qualified.child_rules.len != 0) return error.UnsupportedNesting;
            try rules.append(allocator, prepared);
            _ = try namespaces.consumeRule(allocator, rule, false);
        },
    };

    return .{ .rules = try rules.toOwnedSlice(allocator), .namespaces = namespaces };
}

pub fn deinit(self: *PreparedStylesheet, allocator: std.mem.Allocator) void {
    for (self.rules) |rule| rule.deinit(allocator);
    allocator.free(self.rules);
    self.namespaces.deinit(allocator);
    allocator.destroy(self.namespaces);
}

fn prepareRule(
    allocator: std.mem.Allocator,
    rule: *const syntax.QualifiedRule,
    namespaces: *const namespace.Context,
) !?PreparedRule {
    var input = Stream.init(rule.prelude);
    const list = (try selectors.parseSelectorList(allocator, &input, .{ .namespaces = namespaces })) orelse return null;

    defer allocator.free(list.selectors);
    errdefer for (list.selectors) |selector| selector.deinit(allocator);

    const prepared = try allocator.alloc(PreparedRule.Selector, list.selectors.len);
    errdefer allocator.free(prepared);
    for (list.selectors, prepared) |selector, *entry| entry.* = .{
        .selector = selector,
        .specificity = try Specificity.calculate(allocator, selector),
    };
    return .{ .rule = rule, .selectors = prepared, .context = .{ .namespaces = namespaces } };
}
