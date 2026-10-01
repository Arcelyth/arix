const PreparedStylesheet = @This();

const std = @import("std");
const syntax = @import("../css/syntax/parsing_results.zig");
const Stream = @import("../css/syntax/ComponentValueStream.zig");
const selectors = @import("../css/selectors/parse.zig");
const namespace = @import("../css/namespace.zig");
const Specificity = @import("../css/selectors/Specificity.zig");
const PreparedRule = @import("matching.zig").PreparedRule;
const Origin = @import("cascade/MatchedRule.zig").Origin;
const properties = @import("../css/properties/parse.zig");

rules: []const PreparedRule,
namespaces: *namespace.Context,

/// Parse selectors and typed declarations once per stylesheet.
/// Owns selectors, typed declarations and namespace bindings, but borrows syntax rules
/// and their strings. Keep the syntax stylesheet and its backing storage alive.
/// Invalid selector lists are discarded by the selector parser.
pub fn init(allocator: std.mem.Allocator, stylesheet: *const syntax.Stylesheet, origin: Origin) !PreparedStylesheet {
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
            if (!at_rule.name.eqlAscii("namespace")) @panic("TODO: stylesheet preparation for at-rules other than @namespace");
            _ = try namespaces.consumeRule(allocator, rule, false);
        },
        .qualified_rule => |*qualified| {
            const prepared = (try prepareRule(allocator, qualified, namespaces, origin)) orelse continue;
            errdefer prepared.deinit(allocator);
            if (qualified.child_rules.len != 0) @panic("TODO: nested style rule preparation");
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
    origin: Origin,
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
    return .{
        .rule = rule,
        .declarations = try properties.parseDeclarations(allocator, rule.declarations),
        .origin = origin,
        .selectors = prepared,
        .context = .{ .namespaces = namespaces },
    };
}

test "style PreparedStylesheet: parse selectors and cache specificity" {
    const testing = std.testing;
    const Buffer = @import("../css/syntax/Buffer.zig");
    const Parser = @import("../css/syntax/Parser.zig");

    const alloc = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    var buffer = try Buffer.init(alloc, ".box, #target { width: 100px; }");
    defer buffer.deinit();
    var tokens = buffer.stream(alloc);
    defer tokens.deinit();
    var parser = Parser.init(arena.allocator(), &tokens);
    const stylesheet = try parser.parseStylesheet();
    var prepared = try PreparedStylesheet.init(alloc, &stylesheet, .author);
    defer prepared.deinit(alloc);

    try testing.expectEqual(1, prepared.rules.len);
    const rule = prepared.rules[0];
    try testing.expect(rule.rule == &stylesheet.rules[0].qualified_rule);
    try testing.expectEqual(2, rule.selectors.len);
    try testing.expect(rule.selectors[0].selector.components[0].simple.class.eqlAscii("box"));
    try testing.expect(rule.selectors[1].selector.components[0].simple.id.eqlAscii("target"));
    try testing.expectEqual(Specificity{ .b = 1 }, rule.selectors[0].specificity);
    try testing.expectEqual(Specificity{ .a = 1 }, rule.selectors[1].specificity);
    try testing.expect(rule.rule.declarations[0].name.eqlAscii("width"));
    try testing.expectEqual(Origin.author, rule.origin);
    try testing.expectEqual(@as(f64, 100), rule.declarations[0].value.size.length_percentage.length.value);
}
