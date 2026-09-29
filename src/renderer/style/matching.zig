const std = @import("std");
const Element = @import("../dom/Element.zig");
const QualifiedRule = @import("../css/syntax/parsing_results.zig").QualifiedRule;
const ComplexSelector = @import("../css/selectors/types.zig").ComplexSelector;
const Specificity = @import("../css/selectors/Specificity.zig");
const matching = @import("../css/selectors/matching.zig");
const MatchedRule = @import("cascade/MatchedRule.zig").MatchedRule;

/// Borrowed stylesheet data, prepared once rather than for each element.
pub const PreparedRule = struct {
    /// Need for cascade.
    rule: *const QualifiedRule,
    selectors: []const Selector,
    context: matching.Context = .{},

    pub const Selector = struct {
        selector: ComplexSelector,
        specificity: Specificity,
    };

    /// Release selector storage allocated by stylesheet preparation, not rule data.
    pub fn deinit(self: PreparedRule, allocator: std.mem.Allocator) void {
        for (self.selectors) |entry| entry.selector.deinit(allocator);
        allocator.free(self.selectors);
    }
};

/// Append matches from multiple stylesheets into one list.
pub fn collectMatchedRules(
    allocator: std.mem.Allocator,
    rules: []const PreparedRule,
    element: *const Element,
    matched_rules: *std.ArrayList(MatchedRule),
) !void {
    for (rules) |rule| {
        var specificity: ?Specificity = null;
        for (rule.selectors) |entry| {
            if (!matching.matchComplex(entry.selector.components, element, rule.context)) continue;
            if (specificity == null or entry.specificity.order(specificity.?) == .gt)
                specificity = entry.specificity;
        }
        if (specificity) |value| {
            try matched_rules.append(allocator, .{
                .rule = rule.rule.*,
                .specificity = value,
            });
        }
    }
}

test "style matching: matching specificity and source order" {
    const testing = std.testing;
    const Document = @import("../dom/Document.zig");
    const LocalName = @import("local_name").LocalName;
    const String = @import("../css/String.zig");
    const Declaration = @import("../css/syntax/parsing_results.zig").Declaration;

    const alloc = testing.allocator;
    const document = Document.init(alloc);
    defer document.destroy(alloc);
    document.ty = .DT_Html;
    const element = Element.create(document, try LocalName.fromSlice("div"), .NS_Html, null, null, false, null);
    document.node.appendChild(element.asNode());

    // *
    const universal: PreparedRule.Selector = .{
        .selector = .{ .components = &.{.{ .simple = .{ .universal = .omitted } }} },
        .specificity = .{},
    };
    // div
    const div: PreparedRule.Selector = .{
        .selector = .{ .components = &.{.{ .simple = .{ .type_selector = .{ .name = String.fromSource("div") } } }} },
        .specificity = .{ .c = 1 },
    };
    // #missing
    const missing: PreparedRule.Selector = .{
        .selector = .{ .components = &.{.{ .simple = .{ .id = String.fromSource("missing") } }} },
        .specificity = .{ .a = 1 },
    };
    var first_declarations = [_]Declaration{.{ .name = String.fromSource("width") }};
    var second_declarations = [_]Declaration{.{ .name = String.fromSource("height") }};
    const first: QualifiedRule = .{ .declarations = &first_declarations };
    const second: QualifiedRule = .{ .declarations = &second_declarations };
    const rules = [_]PreparedRule{
        .{ .rule = &first, .selectors = &.{ universal, div, missing } },
        .{ .rule = &first, .selectors = &.{missing} },
        .{ .rule = &second, .selectors = &.{universal} },
    };
    var result: std.ArrayList(MatchedRule) = .empty;
    defer result.deinit(alloc);

    try collectMatchedRules(alloc, &rules, element, &result);
    // Should match universal and div.
    try testing.expectEqual(2, result.items.len);
    try testing.expectEqual(Specificity{ .c = 1 }, result.items[0].specificity);
    try testing.expectEqual(Specificity{}, result.items[1].specificity);
    try testing.expectEqual(first.declarations.ptr, result.items[0].rule.declarations.ptr);
    try testing.expectEqual(second.declarations.ptr, result.items[1].rule.declarations.ptr);

    // A reusable output buffer can collect further rules without clearing earlier matches.
    try collectMatchedRules(alloc, rules[2..], element, &result);
    try testing.expectEqual(3, result.items.len);
}
