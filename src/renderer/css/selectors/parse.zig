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

pub fn parseList(allocator: std.mem.Allocator, input: *Stream, comptime mode: Mode) !?SelectorList {
    return consumeList(allocator, input, mode);
}

pub fn consumeList(allocator: std.mem.Allocator, input: *Stream, comptime mode: Mode) !SelectorList {
    const list: std.ArrayList(ComplexSelector) = .empty;
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
            if (mode.forgiving) break :valid try isValidSelector(parser.components.items);
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

fn isValidSelector(components: []const Component) bool {
    _ = components;
    @panic("TODO:");
}
