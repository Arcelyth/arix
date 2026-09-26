//! Implementation of CSS Selector's grammar's parser.
//! See https://www.w3.org/TR/selectors-4/#grammar
const std = @import("std");
const Stream = @import("../syntax/ComponentValueStream.zig");
const Parser = @import("Parser.zig");
const types = @import("types.zig");
const SelectorList = types.SelectorList;
const ComplexSelector = types.ComplexSelector;
const Component = ComplexSelector.Component;
const Mode = types.Mode;
const grammar = @import("../syntax/grammar.zig");
const namespace = @import("../namespace.zig");

pub const Context = struct {
    namespaces: *const namespace.Context = &.{},
};

pub fn parseSelectorList(allocator: std.mem.Allocator, input: *Stream, context: Context) !?SelectorList {
    return parseList(allocator, input, .{}, context);
}

pub fn parseRealSelectorList(allocator: std.mem.Allocator, input: *Stream, context: Context) !?SelectorList {
    return parseList(allocator, input, .{ .real = true }, context);
}

pub fn parseRelativeSelectorList(allocator: std.mem.Allocator, input: *Stream, context: Context) !?SelectorList {
    return parseList(allocator, input, .{ .relative = true }, context);
}

pub fn parseRelativeRealSelectorList(allocator: std.mem.Allocator, input: *Stream, context: Context) !?SelectorList {
    return parseList(allocator, input, .{ .relative = true, .real = true }, context);
}

pub fn parseCompoundSelectorList(allocator: std.mem.Allocator, input: *Stream, context: Context) !?SelectorList {
    return parseList(allocator, input, .{ .kind = .simple, .real = true }, context);
}

pub fn parseSimpleSelectorList(allocator: std.mem.Allocator, input: *Stream, context: Context) !?SelectorList {
    return parseList(allocator, input, .{ .kind = .simple, .real = true }, context);
}

pub fn parseForgivingSelectorList(allocator: std.mem.Allocator, input: *Stream, context: Context) !?SelectorList {
    return parseList(allocator, input, .{ .real = true, .forgiving = true }, context);
}

pub fn parseList(allocator: std.mem.Allocator, input: *Stream, comptime mode: Mode, context: Context) !?SelectorList {
    const start = input.index;
    return consumeList(allocator, input, mode, context) catch |err| {
        input.restore(start);
        return switch (err) {
            error.InvalidSelector => null,
            else => |failure| failure,
        };
    };
}

pub fn consumeList(allocator: std.mem.Allocator, input: *Stream, comptime mode: Mode, context: Context) !SelectorList {
    var list: std.ArrayList(ComplexSelector) = .empty;
    defer {
        for (list.items) |selector| selector.deinit(allocator);
        list.deinit(allocator);
    }

    var parser = Parser.init(allocator, input);
    defer parser.deinit();

    input.discardWhitespace();
    // Forgiving selector list might be empty.
    if (mode.forgiving and input.empty()) return .{ .selectors = &.{} };
    if (mode.forgiving and !grammar.parseAnyValue(input.values[input.index..])) return error.InvalidSelector;
    while (true) {
        const valid = valid: {
            parser.consumeSelector(mode) catch |err| switch (err) {
                error.InvalidSelector => {
                    if (!mode.forgiving) return err;
                    break :valid false;
                },
                else => return err,
            };
            input.discardWhitespace();
            if (!input.empty() and !input.isToken(.comma)) {
                if (!mode.forgiving) return error.InvalidSelector;
                break :valid false;
            }
            if (mode.forgiving) break :valid isValidSelector(parser.components.items, context.namespaces);
            break :valid true;
        };
        if (valid) {
            try list.append(allocator, .{ .components = try parser.components.toOwnedSlice(allocator) });
        } else {
            parser.components.clearRetainingCapacity();
            // Nested commas are inside component values, so recovery is bounded
            // to the current top-level selector without reparsing nested input.
            while (!input.empty() and !input.isToken(.comma)) input.advance();
        }
        if (input.empty()) break;
        input.advance(); // comma
        input.discardWhitespace();
    }

    return .{
        .selectors = try list.toOwnedSlice(allocator),
    };
}

// https://www.w3.org/TR/selectors-4/#invalid
fn isValidSelector(components: []const Component, namespaces: *const namespace.Context) bool {
    if (components.len == 0) return false;
    for (components) |*component| switch (component.*) {
        .simple => |simple| {
            const prefix = switch (simple) {
                .type_selector => |name| name.namespace,
                .universal => |prefix| prefix,
                .attribute => |attribute| attribute.name.namespace,
                .id, .class => continue,
                // Recognizing the generic :name(args) syntax is not support
                // for a pseudo-selector's own syntax and contextual rules.
                .pseudo_class => return false,
            };
            _ = namespaces.resolve(prefix, .any) catch return false;
        },
        else => {},
    };
    return true;
}

test "CSS selector parsing: parseSelectorList" {
    const testing = std.testing;
    const String = @import("../String.zig");
    const ComponentValue = @import("../syntax/parsing_results.zig").ComponentValue;
    // a.class, b
    const values = [_]ComponentValue{
        .{ .preserved_token = .{ .ident = String.fromSource("a") } },
        .{ .preserved_token = .{ .delim = '.' } },
        .{ .preserved_token = .{ .ident = String.fromSource("class") } },
        .{ .preserved_token = .comma },
        .{ .preserved_token = .whitespace },
        .{ .preserved_token = .{ .ident = String.fromSource("b") } },
    };
    var input = Stream.init(&values);
    const result = try parseSelectorList(testing.allocator, &input, .{});
    try testing.expect(result != null);
    const list = result.?;
    defer list.deinit(testing.allocator);
    try testing.expect(input.empty());
    try testing.expectEqual(2, list.selectors.len);

    const first = list.selectors[0].components;
    try testing.expectEqual(2, first.len);
    try testing.expect(first[0].simple.type_selector.name.eqlAscii("a"));
    try testing.expect(first[1].simple.class.eqlAscii("class"));
    try testing.expectEqual(1, list.selectors[1].components.len);
    try testing.expect(list.selectors[1].components[0].simple.type_selector.name.eqlAscii("b"));

    // A trailing comma invalidates the whole list and restores the cursor.
    input = Stream.init(values[0..4]);
    const invalid = try parseSelectorList(testing.allocator, &input, .{});
    defer if (invalid) |parsed| parsed.deinit(testing.allocator);
    try testing.expect(invalid == null);
    try testing.expectEqual(0, input.index);
}
