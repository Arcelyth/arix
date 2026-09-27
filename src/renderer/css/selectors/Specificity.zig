//! Selector's specificity.
//! See https://www.w3.org/TR/selectors-4/#specificity-rules
const Specificity = @This();

const std = @import("std");
const types = @import("types.zig");
const Parser = @import("Parser.zig");
const Stream = @import("../syntax/ComponentValueStream.zig");
const ComponentValue = @import("../syntax/parsing_results.zig").ComponentValue;

pub const Error = std.mem.Allocator.Error || error{InvalidSelector};

/// Count of ID selectors.
a: u32 = 0,
/// Count of class selectors, attribute selectors, and pseudo-classes.
b: u32 = 0,
/// Count of type selectors and pseudo-elements.
c: u32 = 0,

/// Compare A, then B, then C; lower components never outweigh a higher one.
pub fn order(self: Specificity, other: Specificity) std.math.Order {
    if (self.a != other.a) return std.math.order(self.a, other.a);
    if (self.b != other.b) return std.math.order(self.b, other.b);
    return std.math.order(self.c, other.c);
}

/// Clamp each component independently rather than wrapping or carrying.
pub fn add(self: *Specificity, other: Specificity) void {
    self.a +|= other.a;
    self.b +|= other.b;
    self.c +|= other.c;
}

/// Calculate a valid selector's specificity, independently of which element matches.
/// Selector validity is the caller's responsibility. The allocator is used only
/// to parse selector arguments still stored as component values in the AST.
pub fn calculate(allocator: std.mem.Allocator, selector: types.ComplexSelector) Error!Specificity {
    var result: Specificity = .{};
    for (selector.components) |component| switch (component) {
        .combinator => {},
        .pseudo_element => result.add(.{ .c = 1 }),
        .simple => |simple| switch (simple) {
            .id => result.add(.{ .a = 1 }),
            .class, .attribute => result.add(.{ .b = 1 }),
            .type_selector => result.add(.{ .c = 1 }),
            .universal => {},
            .pseudo_class => |pseudo| result.add(try pseudoClass(allocator, pseudo)),
        },
    };
    return result;
}

pub fn pseudoClass(allocator: std.mem.Allocator, pseudo: types.PseudoClassSelector) !Specificity {
    const arguments = pseudo.arguments orelse return .{ .b = 1 };
    if (pseudo.name.eqlAscii("where")) return .{};
    if (pseudo.name.eqlAscii("is") or pseudo.name.eqlAscii("not") or pseudo.name.eqlAscii("has"))
        return maxArgument(allocator, arguments, pseudo.name.eqlAscii("has"));

    var result: Specificity = .{ .b = 1 };
    if (pseudo.name.eqlAscii("nth-child") or pseudo.name.eqlAscii("nth-last-child")) {
        // Only a top-level `of` introduces the selector list; nested component
        // values cannot be mistaken for this separator. An+B contributes zero.
        for (arguments, 0..) |value, i| {
            if (value == .preserved_token and value.preserved_token == .ident and
                value.preserved_token.ident.eqlAscii("of"))
            {
                result.add(try maxArgument(allocator, arguments[i + 1 ..], false));
                break;
            }
        }
    }
    return result;
}

/// Return the maximum specificity among the selector arguments.
fn maxArgument(allocator: std.mem.Allocator, values: []const ComponentValue, relative: bool) Error!Specificity {
    var input = Stream.init(values);
    var parser = Parser.init(allocator, &input);
    defer parser.deinit();
    var result: Specificity = .{};
    input.discardWhitespace();
    // An empty, validated forgiving list has no contributing selectors.
    if (input.empty()) return result;
    while (true) {
        // A leading relative combinator contributes nothing to specificity.
        if (relative) {
            _ = parser.consumeCombinator();
            input.discardWhitespace();
        }
        try parser.consumeSelector(.{ .real = true });
        const current = try calculate(allocator, .{ .components = parser.components.items });
        if (current.order(result) == .gt) result = current;
        parser.components.clearRetainingCapacity();
        input.discardWhitespace();
        if (input.empty()) return result;
        if (!input.isToken(.comma)) return error.InvalidSelector;
        input.advance();
        input.discardWhitespace();
    }
}

test "CSS specificity: section 15 examples" {
    const Buffer = @import("../syntax/Buffer.zig");
    const SyntaxParser = @import("../syntax/Parser.zig");
    const parse = @import("parse.zig");
    // These cases from spec.
    const cases = .{
        .{ "*", Specificity{} },
        .{ "LI", Specificity{ .c = 1 } },
        .{ "UL LI", Specificity{ .c = 2 } },
        .{ "UL OL+LI", Specificity{ .c = 3 } },
        .{ "H1 + *[REL=up]", Specificity{ .b = 1, .c = 1 } },
        .{ "UL OL LI.red", Specificity{ .b = 1, .c = 3 } },
        .{ "LI.red.level", Specificity{ .b = 2, .c = 1 } },
        .{ "#x34y", Specificity{ .a = 1 } },
        .{ "#s12:not(FOO)", Specificity{ .a = 1, .c = 1 } },
        .{ ".foo :is(.bar, #baz)", Specificity{ .a = 1, .b = 1 } },
        .{ ":is(em, #foo)", Specificity{ .a = 1 } },
        .{ ".qux:where(em, #foo#bar#baz)", Specificity{ .b = 1 } },
        .{ ":nth-child(even of li, .item)", Specificity{ .b = 2 } },
        .{ ":not(em, strong#foo)", Specificity{ .a = 1, .c = 1 } },
    };
    inline for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        var buffer = try Buffer.init(allocator, case[0]);
        defer buffer.deinit();
        var token_stream = buffer.stream(allocator);
        defer token_stream.deinit();
        var syntax = SyntaxParser.init(allocator, &token_stream);
        var input = Stream.init(try syntax.parseListOfComponentValues());
        const list = (try parse.parseSelectorList(allocator, &input, .{})).?;
        try std.testing.expectEqual(case[1], try calculate(allocator, list.selectors[0]));
    }
}

