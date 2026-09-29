const std = @import("std");
const Element = @import("../dom/Element.zig");
const QualifiedRule = @import("../css/syntax/parsing_results.zig").QualifiedRule;
const ComplexSelector = @import("../css/selectors/types.zig").ComplexSelector;
const Specificity = @import("../css/selectors/Specificity.zig");
const matching = @import("../css/selectors/matching.zig");
const MatchedRule = @import("cascade/MatchedRule.zig").MatchedRule;
const Origin = @import("cascade/MatchedRule.zig").Origin;
const Declaration = @import("../css/properties/types.zig").Declaration;

/// Prepared for matching.
/// Borrowed stylesheet data, prepared once rather than for each element.
pub const PreparedRule = struct {
    /// Original syntax rule.
    rule: *const QualifiedRule,
    declarations: []const Declaration,
    origin: Origin,
    selectors: []const Selector,
    context: matching.Context = .{},

    pub const Selector = struct {
        selector: ComplexSelector,
        specificity: Specificity,
    };

    /// Release prepared selectors and typed declarations, not syntax rule data.
    pub fn deinit(self: PreparedRule, allocator: std.mem.Allocator) void {
        for (self.selectors) |entry| entry.selector.deinit(allocator);
        allocator.free(self.selectors);
        allocator.free(self.declarations);
    }
};

/// Append matches in source order. Call in stylesheet order within each origin.
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
                .declarations = rule.declarations,
                .specificity = value,
                .origin = rule.origin,
            });
        }
    }
}

test "style matching: matching specificity and source order" {
    const testing = std.testing;
    const Document = @import("../dom/Document.zig");
    const LocalName = @import("local_name").LocalName;
    const String = @import("../css/String.zig");

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
    const first_declarations = [_]Declaration{.{ .property = .width, .value = .{ .size = .auto } }};
    const second_declarations = [_]Declaration{.{ .property = .height, .value = .{ .size = .auto } }};
    const first: QualifiedRule = .{};
    const second: QualifiedRule = .{};
    const rules = [_]PreparedRule{
        .{
            .rule = &first,
            .declarations = &first_declarations,
            .origin = .author,
            .selectors = &.{ universal, div, missing },
        },
        .{
            .rule = &first,
            .declarations = &first_declarations,
            .origin = .author,
            .selectors = &.{missing},
        },
        .{
            .rule = &second,
            .declarations = &second_declarations,
            .origin = .user,
            .selectors = &.{universal},
        },
    };
    var result: std.ArrayList(MatchedRule) = .empty;
    defer result.deinit(alloc);

    try collectMatchedRules(alloc, &rules, element, &result);
    // Should match universal and div.
    try testing.expectEqual(2, result.items.len);
    try testing.expectEqual(Specificity{ .c = 1 }, result.items[0].specificity);
    try testing.expectEqual(Specificity{}, result.items[1].specificity);
    try testing.expectEqual(&first_declarations[0], &result.items[0].declarations[0]);
    try testing.expectEqual(&second_declarations[0], &result.items[1].declarations[0]);
    try testing.expectEqual(Origin.author, result.items[0].origin);
    try testing.expectEqual(Origin.user, result.items[1].origin);

    // A reusable output buffer can collect further rules without clearing earlier matches.
    try collectMatchedRules(alloc, rules[2..], element, &result);
    try testing.expectEqual(3, result.items.len);
}
