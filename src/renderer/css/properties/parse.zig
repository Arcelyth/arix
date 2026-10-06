const std = @import("std");
const syntax = @import("../syntax/parsing_results.zig");
const Stream = @import("../syntax/ComponentValueStream.zig");
const String = @import("../String.zig");
const registry = @import("registry.zig");
const types = @import("types.zig");
const Declaration = types.Declaration;
const Value = types.Value;
const CSSWideKeyword = types.CSSWideKeyword;

/// Append specified values, expanding shorthands into longhands.
/// Unknown properties and invalid values are ignored.
pub fn parseDeclaration(
    allocator: std.mem.Allocator,
    declaration: *const syntax.Declaration,
    result: *std.ArrayList(Declaration),
) !void {
    const property = registry.fromName(declaration.name) orelse return;
    const ids: []const registry.PropertyId = switch (property) {
        .longhand => |id| &.{id},
        .shorthand => |shorthand| shorthand.longhands,
    };
    for (declaration.value) |value| {
        if (value == .function and value.function.name.eqlAscii("var"))
            @panic("TODO: CSS custom property substitution");
    }

    var input = Stream.init(declaration.value);
    input.discardWhitespace();
    // A shorthand can expand to at most all registered longhands.
    var storage: [std.enums.values(registry.PropertyId).len]Value = undefined;
    const values = storage[0..ids.len];
    parse: {
        if (input.peekToken()) |token| {
            if (token.* == .ident) {
                if (parseCSSWideKeyword(token.ident)) |keyword| {
                    input.advance();
                    @memset(values, .{ .css_wide = keyword });
                    break :parse;
                }
            }
        }
        switch (property) {
            .longhand => |id| values[0] = registry.parseValue(id, &input) orelse return,
            .shorthand => |shorthand| if (!shorthand.parse(&input, values)) return,
        }
    }
    input.discardWhitespace();
    if (!input.empty()) return;
    try result.ensureUnusedCapacity(allocator, ids.len);
    for (ids, values) |id, value| {
        result.appendAssumeCapacity(.{ .property = id, .value = value, .important = declaration.important });
    }
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
        try parseDeclaration(allocator, declaration, &result);
    }
    return result.toOwnedSlice(allocator);
}

test "properties parse: longhands, shorthands and invalid declarations" {
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
        \\    BoRdEr-LeFt: ReVeRt-LaYeR !important;
        \\    border: inherit red;
        \\    border: 2px solid red blue;
        \\    border-color:;
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
        .{
            .property = .border_left_width,
            .value = .{ .css_wide = .revert_layer },
            .important = true,
        },
        .{
            .property = .border_left_style,
            .value = .{ .css_wide = .revert_layer },
            .important = true,
        },
        .{
            .property = .border_left_color,
            .value = .{ .css_wide = .revert_layer },
            .important = true,
        },
    };
    try testing.expectEqualDeep(&expected, declarations);
}
