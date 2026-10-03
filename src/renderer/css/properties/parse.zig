const std = @import("std");
const syntax = @import("../syntax/parsing_results.zig");
const Stream = @import("../syntax/ComponentValueStream.zig");
const String = @import("../String.zig");
const registry = @import("registry.zig");
const types = @import("types.zig");
const Declaration = types.Declaration;
const Value = types.Value;
const CSSWideKeyword = types.CSSWideKeyword;

/// Parse a syntax-parsed declaration to one use specified value.
/// Unknown properties and invalid values return null.
pub fn parseDeclaration(declaration: *const syntax.Declaration) ?Declaration {
    const id = registry.fromName(declaration.name) orelse return null;
    for (declaration.value) |value| {
        if (value == .function and value.function.name.eqlAscii("var"))
            @panic("TODO: CSS custom property substitution");
    }

    var input = Stream.init(declaration.value);
    input.discardWhitespace();
    const value: Value = value: {
        if (input.peekToken()) |token| {
            if (token.* == .ident) {
                if (parseCSSWideKeyword(token.ident)) |keyword| {
                    input.advance();
                    break :value .{ .css_wide = keyword };
                }
            }
        }
        break :value registry.parseValue(id, &input) orelse return null;
    };
    input.discardWhitespace();
    if (!input.empty()) return null;
    return .{ .property = id, .value = value, .important = declaration.important };
}

fn parseCSSWideKeyword(name: String) ?CSSWideKeyword {
    if (name.eqlAscii("initial")) return .initial;
    if (name.eqlAscii("inherit")) return .inherit;
    if (name.eqlAscii("unset")) return .unset;
    if (name.eqlAscii("revert")) return .revert;
    if (name.eqlAscii("revert-layer")) return .revert_layer;
    return null;
}

pub fn parseDeclarations(allocator: std.mem.Allocator, declarations: []const syntax.Declaration) ![]Declaration {
    var result: std.ArrayList(Declaration) = .empty;
    errdefer result.deinit(allocator);

    for (declarations) |*declaration| {
        if (parseDeclaration(declaration)) |value| try result.append(allocator, value);
    }
    return result.toOwnedSlice(allocator);
}

test "properties parse: typed values and invalid declarations" {
    const testing = std.testing;
    const Buffer = @import("../syntax/Buffer.zig");
    const Parser = @import("../syntax/Parser.zig");
    const alloc = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    var buffer = try Buffer.init(alloc,
        \\div {
        \\    WIDTH: 100px !important;
        \\    height: inherit;
        \\    width: red;
        \\    unknown: 1px;
        \\    width: auto;
        \\}
    );
    defer buffer.deinit();

    var tokens = buffer.stream(alloc);
    defer tokens.deinit();

    var parser = Parser.init(arena.allocator(), &tokens);
    const rule = try parser.parseRule();
    const declarations = try parseDeclarations(alloc, rule.qualified_rule.declarations);
    defer alloc.free(declarations);

    const expected = [_]Declaration{
        .{
            .property = .width,
            .value = .{
                .size = .{
                    .length_percentage = .{
                        .length = .{ .value = 100, .unit = .px },
                    },
                },
            },
            .important = true,
        },
        .{
            .property = .height,
            .value = .{ .css_wide = .inherit },
        },
        .{
            .property = .width,
            .value = .{ .size = .auto },
        },
    };
    try testing.expectEqualDeep(&expected, declarations);
}
